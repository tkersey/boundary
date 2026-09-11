import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { checkCore, command } from '../../tools/v2/formal.mjs';
import { generateRefusals } from '../../tools/v2/rejection_certify.mjs';

const [formalArgument, invocationArgument, refusalArgument, baseArgument, ...extra] = process.argv.slice(2);
assert.ok(formalArgument && invocationArgument && refusalArgument && baseArgument && !extra.length,
  'usage: rejection_artifacts.mjs <formal-root> <invocations.json> <refusals.json> <execution-certificates>');
const root = resolve(formalArgument), baseDirectory = resolve(baseArgument);
const observed = new Map();
async function capture(path) {
  const value = await readFile(path);
  if (observed.has(path)) assert.deepEqual(value, observed.get(path), 'refusal.input_changed');
  observed.set(path, value);
  return value;
}
const invocations = JSON.parse(await capture(resolve(invocationArgument)));
const physical = JSON.parse(await capture(resolve(refusalArgument)));
assert.ok(Array.isArray(invocations) && invocations.length);
assert.ok(Array.isArray(physical.records) && physical.records.length);
assert.equal(new Set(invocations.map((row) => row.name)).size, invocations.length);
const parent = join(root, '.cache/refusal-artifacts');
await mkdir(parent, { recursive: true });
const directory = await mkdtemp(join(parent, 'run-'));
const needed = new Set(physical.records.map((row) => row.case));
const bases = [];
for (const name of await readdir(baseDirectory)) {
  if (!/^BoundaryCertificateExecution[0-9a-f]{64}\.json$/.test(name)) continue;
  const metadata = JSON.parse(await capture(join(baseDirectory, name)));
  if (!needed.has(metadata.case)) continue;
  assert.match(metadata.module, /^BoundaryCertificateExecution[0-9a-f]{64}$/);
  assert.equal(metadata.path, join(baseDirectory, `${metadata.module}.lean`));
  const group = invocations.find((row) => row.name === metadata.case);
  assert.ok(group, 'refusal.unknown_base_case');
  const records = [];
  for (const transition of group.transitions) records.push({ input: [...await capture(transition.input)],
    output: [...await capture(transition.output)] });
  assert.deepEqual(metadata.claims, [{ name: `${metadata.module}.certificate`, kind: 'initial-execution',
    image: [...await capture(group.image)], records }]);
  const source = await capture(metadata.path);
  metadata.path = join(directory, `${metadata.module}.lean`);
  await writeFile(metadata.path, source);
  await writeFile(join(directory, `${metadata.module}.json`), JSON.stringify(metadata));
  bases.push(metadata);
}
assert.equal(bases.length, needed.size, 'refusal.missing_image_proofs');
assert.equal(new Set(bases.map((base) => base.case)).size, needed.size);

const frozen = [], subjects = [];
for (const [index, row] of physical.records.entries()) {
  const copy = { ...row }, data = {};
  for (const role of ['input', 'output', 'error', 'inputAfter', 'retryInput', 'retryOutput']) {
    const value = await capture(row[role]);
    data[role] = [...value];
    copy[role] = join(directory, `${index}-${role}.bin`);
    await writeFile(copy[role], value);
  }
  const base = bases.find((base) => base.case === row.case);
  assert.ok(base.claims[0].records.some((record) =>
    JSON.stringify(record) === JSON.stringify({ input: data.retryInput, output: data.retryOutput })),
  'refusal.retry_not_in_certified_execution');
  frozen.push(copy);
  subjects.push({ image: base.claims[0].image, record: { backend: row.producer,
    input: data.input, output: data.output, diagnostic: data.error, inputAfter: data.inputAfter, status: row.status } });
}
const frozenManifest = join(directory, 'records.json');
await writeFile(frozenManifest, JSON.stringify({ ...physical, records: frozen }));
const refusals = await generateRefusals(frozenManifest, directory, directory);
assert.equal(refusals.length, subjects.length);
for (const [index, certificate] of refusals.entries()) {
  assert.deepEqual(certificate.claims, [{ name: `${certificate.module}.certificate`, kind: 'refusal', ...subjects[index] }]);
  assert.deepEqual(certificate.dependencies, [bases.find((base) => base.case === certificate.case).module]);
}
const certificates = [...bases, ...refusals];
const proof = await checkCore(root, { certificates });
console.log(`refusal artifacts: ${refusals.length} exact records and valid retries, kernel/trust/fresh replay passed`);

// Claim mutations alter the audit's expected type, so exercise that boundary
// against the already checked proof objects. A changed theorem is recompiled.
// Full compilation and replay bracket these negative controls.
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
  assert.notEqual(result.code, 0, 'refusal.mutation_accepted');
  assert.match(result.text, /trust\.claim_type/);
}
async function compile(certificate) {
  const result = await command('lake', ['env', 'lean', '-M', '8192', '-DwarningAsError=true',
    `--root=${dirname(certificate.path)}`, '-o', join(root, '.lake/build/lib/lean', `${certificate.module}.olean`),
    certificate.path], root, { quiet: true });
  assert.equal(result.code, 0, result.text);
  assert.equal(result.signal, null);
}
const original = refusals[0], source = await readFile(original.path, 'utf8');
try {
  const changed = source.replace(/theorem certificate :[\s\S]*?\nend /,
    'theorem certificate : True := .intro\nend ');
  assert.notEqual(changed, source);
  await writeFile(original.path, changed);
  await compile(original);
  await auditMutation(certificates);
} finally {
  await writeFile(original.path, source);
  await compile(original);
}
for (const role of ['image', 'input', 'output', 'diagnostic', 'inputAfter', 'status', 'backend']) {
  const changed = structuredClone(certificates);
  const claim = changed.find((certificate) => certificate.module === original.module).claims[0];
  if (role === 'status') claim.record.status += 1;
  else if (role === 'backend') claim.record.backend = claim.record.backend === 'native' ? 'wasm' : 'native';
  else {
    const value = role === 'image' ? claim.image : claim.record[role];
    if (value.length) value[value.length - 1] ^= 1; else value.push(0);
  }
  await auditMutation(changed);
}
const restored = await checkCore(root, { certificates, quiet: true });
assert.deepEqual(restored.claims, proof.claims);
for (const [path, value] of observed) assert.deepEqual(await readFile(path), value, 'refusal.input_changed');
console.log('refusal artifacts: false theorem and changed image/record fields rejected; clean proof and replay restored');
