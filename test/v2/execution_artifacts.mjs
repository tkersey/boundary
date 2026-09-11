import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { certificateClosure, checkCore, command } from '../../tools/v2/formal.mjs';

const [formalArgument, manifestArgument, ...selection] = process.argv.slice(2);
assert.ok(formalArgument && manifestArgument,
  'usage: execution_artifacts.mjs <formal-root> <invocation-manifest> [case-names]');
const root = resolve(formalArgument), manifestPath = resolve(manifestArgument);
const hashRules = await command('lake', ['env', 'lean', '-M', '4096', '-DwarningAsError=true',
  resolve(import.meta.dirname, 'execution_hash_rules.lean')], root);
assert.equal(hashRules.code, 0, hashRules.text);
assert.equal(hashRules.signal, null);
const manifestBytes = await readFile(manifestPath);
const manifest = JSON.parse(manifestBytes);
assert.ok(Array.isArray(manifest) && manifest.length, 'execution.empty_manifest');
assert.equal(new Set(manifest.map((group) => group.name)).size, manifest.length,
  'execution.duplicate_cases');
for (const name of selection) assert.ok(manifest.some((group) => group.name === name),
  `execution.missing_case: ${name}`);
const groups = manifest.filter((group) => !selection.length || selection.includes(group.name));
const parent = join(root, '.cache/execution-artifacts');
await mkdir(parent, { recursive: true });
const directory = await mkdtemp(join(parent, 'run-'));

// Freeze all producer inputs once. The subject comparison below binds the
// generated claims independently of both the producer's filenames and verdict.
const frozen = [], subjects = [], images = new Map();
for (const [index, group] of groups.entries()) {
  // Cases sharing one image also share its frozen input and admission witness.
  // Retaining that identity lets the producer reuse its checked program data.
  let staged = images.get(group.image);
  if (!staged) {
    const image = await readFile(group.image), witness = await readFile(`${group.image}.graph.borrow.json`);
    const path = join(directory, `${index}.bpi2`);
    await writeFile(path, image); await writeFile(`${path}.graph.borrow.json`, witness);
    staged = { image, witness, path };
    images.set(group.image, staged);
  }
  const { image, path: imagePath } = staged;
  const transitions = [], records = [];
  for (const [ordinal, transition] of group.transitions.entries()) {
    const input = await readFile(transition.input), output = await readFile(transition.output);
    const inputPath = join(directory, `${index}-${ordinal}.pki2`);
    const outputPath = join(directory, `${index}-${ordinal}.pko2`);
    await writeFile(inputPath, input); await writeFile(outputPath, output);
    transitions.push({ ...transition, input: inputPath, output: outputPath });
    records.push({ input: [...input], output: [...output] });
  }
  assert.ok(records.length, `execution.empty_segment: ${group.name}`);
  frozen.push({ ...group, image: imagePath, transitions });
  subjects.push({ name: group.name, image: [...image], records });
}
const frozenManifest = join(directory, 'inputs.json');
await writeFile(frozenManifest, JSON.stringify(frozen));
for (const args of [['build', 'boundary-execution-producer'],
  ['exe', 'boundary-execution-producer', frozenManifest, directory]]) {
  const result = await command('lake', args, root);
  assert.equal(result.code, 0, result.text);
  assert.equal(result.signal, null);
}
const certificates = [];
for (const name of await readdir(directory)) {
  if (!/^BoundaryCertificateExecution[0-9a-f]{64}\.json$/.test(name)) continue;
  const certificate = JSON.parse(await readFile(join(directory, name), 'utf8'));
  assert.equal(certificate.status, 'candidate');
  assert.equal(certificate.path, join(directory, `${certificate.module}.lean`));
  assert.equal(certificate.claims.length, 1);
  const subject = subjects.find((subject) => subject.name === certificate.case);
  assert.ok(subject, 'execution.unrequested_subject');
  assert.deepEqual(certificate.claims[0], { name: `${certificate.module}.certificate`,
    kind: 'initial-execution', image: subject.image, records: subject.records });
  certificates.push(certificate);
}
assert.equal(certificates.length, subjects.length, 'execution.missing_certificates');
assert.equal(new Set(certificates.map((certificate) => certificate.case)).size, subjects.length);
const artifacts = certificateClosure(certificates);
for (const artifact of artifacts)
  assert.equal(artifact.path, join(directory, `${artifact.module}.lean`), 'execution.dependency_path');
assert.deepEqual((await readdir(directory)).filter((name) => name.endsWith('.lean')).sort(),
  artifacts.map((artifact) => `${artifact.module}.lean`).sort(), 'execution.unlisted_generated_file');
const sharedImages = new Map();
for (const group of groups) {
  const certificate = certificates.find((candidate) => candidate.case === group.name);
  const imageModule = certificate.dependencies?.find((dependency) =>
    /^BoundaryCertificateImage[0-9a-f]{64}$/.test(dependency.module))?.module;
  assert.match(imageModule, /^BoundaryCertificateImage[0-9a-f]{64}$/, 'execution.image_proof');
  const previous = sharedImages.get(group.image);
  if (previous) assert.equal(imageModule, previous, 'execution.duplicated_image_proof');
  sharedImages.set(group.image, imageModule);
}


const proof = await checkCore(root, { certificates });
console.log(`execution artifacts: ${certificates.length} exact subjects, kernel/trust/fresh replay passed`);

// A changed expected claim exercises the audit boundary against the checked
// proof object. Recompile changed theorem sources; full compilation and fresh
// replay bracket the controls and remain mandatory for acceptance.
async function auditMutation(changedCertificates) {
  const modules = structuredClone(proof.modules);
  for (const certificate of changedCertificates) {
    modules.find((entry) => entry.name === certificate.module).sha256 =
      createHash('sha256').update(await readFile(certificate.path)).digest('hex');
  }
  const inventory = { format: 'boundary.formal-inventory/v1', modules,
    roots: ['Trust', ...modules.filter((entry) => entry.kind === 'certificate').map((entry) => entry.name)],
    claims: changedCertificates.flatMap((certificate) => certificate.claims) };
  const path = join(directory, 'mutation-inventory.json');
  await writeFile(path, JSON.stringify(inventory));
  const result = await command('lake', ['exe', 'boundary-trust', path, join(directory, 'mutation-audit.json')],
    root, { quiet: true });
  assert.equal(result.signal, null);
  assert.notEqual(result.code, 0, 'execution.mutation_accepted');
  assert.match(result.text, /trust\.claim_type/);
}
async function compile(certificate) {
  const result = await command('lake', ['env', 'lean', '-M', '8192', '-DwarningAsError=true',
    `--root=${dirname(certificate.path)}`, '-o', join(root, '.lake/build/lib/lean', `${certificate.module}.olean`),
    certificate.path], root, { quiet: true });
  assert.equal(result.code, 0, result.text);
  assert.equal(result.signal, null);
}
const original = certificates.find((certificate) => certificate.claims[0].records.length > 1) ?? certificates[0];
const source = await readFile(original.path, 'utf8');
try {
  const changed = source.replace(/theorem certificate :[\s\S]*?\nend /,
    'theorem certificate : True := .intro\nend ');
  assert.notEqual(changed, source, 'execution.mutation_not_applied');
  await writeFile(original.path, changed);
  await compile(original);
  await auditMutation(certificates);
} finally {
  await writeFile(original.path, source);
  await compile(original);
}

for (const role of ['image', 'input', 'output', 'missing-final-record']) {
  const changed = structuredClone(certificates);
  const claim = changed.find((certificate) => certificate.module === original.module).claims[0];
  if (role === 'missing-final-record') {
    if (claim.records.length === 1) continue;
    claim.records.pop();
  } else {
    const bytes = role === 'image' ? claim.image : claim.records[0][role];
    bytes[bytes.length - 1] ^= 1;
  }
  await auditMutation(changed);
}
const restored = await checkCore(root, { certificates, quiet: true, reuse: proof });
assert.deepEqual(restored.claims, proof.claims);
assert.deepEqual(await readFile(manifestPath), manifestBytes, 'execution.manifest_changed');
for (const [path, image] of images)
  assert.deepEqual(await readFile(`${path}.graph.borrow.json`), image.witness, 'execution.witness_changed');
for (const [index, group] of groups.entries()) {
  assert.deepEqual([...await readFile(group.image)], subjects[index].image, 'execution.image_changed');
  for (const [ordinal, transition] of group.transitions.entries()) {
    assert.deepEqual([...await readFile(transition.input)], subjects[index].records[ordinal].input,
      'execution.input_changed');
    assert.deepEqual([...await readFile(transition.output)], subjects[index].records[ordinal].output,
      'execution.output_changed');
  }
}
console.log('execution artifacts: false theorem and changed complete subjects rejected; clean proof and replay restored');
