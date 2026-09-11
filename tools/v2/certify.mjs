import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, readdir, realpath, rename, rm, stat, writeFile } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { certificateClosure, checkCore, command, discover } from './formal.mjs';
import { parseExactJson } from './exact_json.mjs';

const repository = resolve(import.meta.dirname, '../..');
const formal = join(repository, 'semantics/v2');
const usage = 'usage: boundary-certify --image FILE (--source FILE | --execution FILE) --witness FILE --output FILE';
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const dataJson = (value) => JSON.stringify(value,
  (_, field) => typeof field === 'bigint' ? JSON.rawJSON(field.toString()) : field);
class Diagnostic extends Error {
  constructor(exitCode, code, message, role = null) {
    super(message); Object.assign(this, { exitCode, code, role });
  }
}
function fail(exitCode, code, message, role) { throw new Diagnostic(exitCode, code, message, role); }
function object(value, required, role) {
  if (!value || Array.isArray(value) || typeof value !== 'object' ||
      Object.keys(value).length !== required.length || required.some((key) => !Object.hasOwn(value, key)))
    fail(1, 'input.fields', `Expected exactly: ${required.join(', ')}`, role);
}
function bytes(value, role) {
  if (!Array.isArray(value) || value.some((byte) => !Number.isInteger(byte) || byte < 0 || byte > 255))
    fail(1, 'input.bytes', 'Expected a complete array of bytes', role);
  return Buffer.from(value);
}
function json(value, role) {
  try { return parseExactJson(value); }
  catch (error) { fail(1, 'input.json', error.message, role); }
}
function options(args) {
  const result = {};
  for (let index = 0; index < args.length; index += 2) {
    const flag = args[index], value = args[index + 1];
    if (!['--source', '--image', '--execution', '--witness', '--output'].includes(flag) ||
        !value || value.startsWith('--') || Object.hasOwn(result, flag.slice(2)))
      fail(64, 'usage', usage);
    result[flag.slice(2)] = resolve(value);
  }
  if (!result.image || !result.witness || !result.output || Boolean(result.source) === Boolean(result.execution))
    fail(64, 'usage', usage);
  return result;
}
async function checkedCommand(file, args, { quiet = true } = {}) {
  let result;
  try { result = await command(file, args, formal, { quiet }); }
  catch (error) { fail(2, 'tool.unavailable', error.message); }
  if (result.code !== 0 || result.signal)
    fail(2, 'tool.failed', `${file} ${args.join(' ')} (${result.code ?? result.signal})\n${result.text}`);
  return result;
}
async function executable(path, role) {
  const resolved = await realpath(path);
  const value = await readFile(resolved);
  return { role, path: resolved, length: value.length, sha256: sha256(value) };
}
async function toolIdentities() {
  if (process.version !== 'v26.8.1') fail(2, 'tool.node_version', `Expected Node v26.8.1; found ${process.version}`);
  const lean = await checkedCommand('lake', ['env', 'lean', '--version']);
  if (!/version 4\.33\.1[, ]/.test(lean.text) || !lean.text.includes('819816b2e0a3bf405af45ae5c7af2491d8f5bee6'))
    fail(2, 'tool.lean_version', lean.text.trim());
  const prefix = (await checkedCommand('lake', ['env', 'lean', '--print-prefix'])).text.trim();
  return [await executable(process.execPath, 'node'), await executable(join(prefix, 'bin/lean'), 'lean'),
    await executable(join(prefix, 'bin/leanchecker'), 'leanchecker')];
}
const tooling = ['certify.mjs', 'certify.lean', 'formal.mjs', 'exact_json.mjs', 'execution_producer.lean',
  'ExecutionProof.lean', 'ProgramProof.lean', 'InvocationWitness.lean', 'GraphWitness.lean', 'BorrowWitness.lean'];
async function sources() {
  const core = await discover(formal);
  const files = core.modules.map((module) => ({
    path: `semantics/v2/${module.name.replaceAll('.', '/')}.lean`, sha256: module.sha256,
  }));
  for (const path of ['semantics/v2/lakefile.toml', 'semantics/v2/lean-toolchain',
    'semantics/v2/lake-manifest.json', ...tooling.map((file) => `tools/v2/${file}`)])
    files.push({ path, sha256: sha256(await readFile(join(repository, path))) });
  files.sort((left, right) => left.path.localeCompare(right.path, 'en'));
  return { files, sha256: sha256(Buffer.from(JSON.stringify(files))) };
}
async function boundaryIdentity(snapshot) {
  const head = await command('git', ['rev-parse', 'HEAD'], repository, { quiet: true });
  if (head.code !== 0 || head.signal) fail(2, 'source.git_identity', head.text);
  const status = await command('git', ['status', '--porcelain=v1', '--untracked-files=all', '--',
    ...snapshot.files.map((file) => file.path)], repository, { quiet: true });
  if (status.code !== 0 || status.signal) fail(2, 'source.git_identity', status.text);
  return { revision: head.text.trim(), dirty: Boolean(status.text.trim()),
    proof_source_sha256: snapshot.sha256, proof_sources: snapshot.files };
}
async function unchanged(inputs, snapshot, tools) {
  for (const input of inputs)
    if (!(await readFile(input.path)).equals(input.bytes))
      fail(2, 'input.changed', 'Input changed while certification was running', input.role);
  if ((await sources()).sha256 !== snapshot.sha256)
    fail(2, 'source.changed', 'Proof sources or verification tools changed while certification was running');
  for (const tool of tools)
    if (sha256(await readFile(tool.path)) !== tool.sha256)
      fail(2, 'tool.changed', `Executable changed: ${tool.role}`);
}
async function atomicResult(path, result) {
  // A temporary sibling and rename replace an output hardlink without writing
  // through it. The caller's input path is checked separately before this step.
  const temporary = join(dirname(path), `.${basename(path)}.${process.pid}.${createHash('sha256')
    .update(String(process.hrtime.bigint())).digest('hex').slice(0, 16)}.pending`);
  try {
    await writeFile(temporary, `${JSON.stringify(result, null, 2)}\n`, { flag: 'wx' });
    await rename(temporary, path);
  } finally { await rm(temporary, { force: true }); }
}
async function certifyExecution(input, witnessInput, image, directory) {
  const execution = json(input, 'execution'), witness = json(witnessInput, 'witness');
  object(execution, ['format', 'completion', 'records'], 'execution');
  object(witness, ['format', 'image_bytes', 'borrow', 'steps'], 'witness');
  if (execution.format !== 'boundary.execution-segment/v1' || execution.completion !== 'complete')
    fail(1, 'execution.format', 'Expected a complete boundary.execution-segment/v1 segment', 'execution');
  if (witness.format !== 'boundary.execution-witness/v1')
    fail(1, 'witness.format', 'Expected boundary.execution-witness/v1', 'witness');
  if (!bytes(witness.image_bytes, 'witness.image_bytes').equals(image))
    fail(1, 'witness.image', 'Witness image differs from the complete image input', 'witness');
  object(witness.borrow, ['program_bytes', 'paths', 'queries', 'requirements'], 'witness.borrow');
  if (!Array.isArray(execution.records) || !execution.records.length ||
      !Array.isArray(witness.steps) || witness.steps.length !== execution.records.length)
    fail(1, 'execution.records', 'Each invocation requires one finite path witness', 'execution');
  const imagePath = join(directory, 'program.bpi2'), transitions = [], records = [];
  await writeFile(imagePath, image);
  await writeFile(`${imagePath}.graph.borrow.json`, dataJson(witness.borrow));
  for (const [index, record] of execution.records.entries()) {
    object(record, ['input', 'output'], `execution.records[${index}]`);
    const inputBytes = bytes(record.input, `execution.records[${index}].input`);
    const outputBytes = bytes(record.output, `execution.records[${index}].output`);
    const count = witness.steps[index];
    if (!Number.isSafeInteger(count) || count < 0)
      fail(1, 'witness.steps', 'Expected an exactly represented nonnegative path length', 'witness');
    const inputPath = join(directory, `${index}.pki2`), outputPath = join(directory, `${index}.pko2`);
    await writeFile(inputPath, inputBytes); await writeFile(outputPath, outputBytes);
    transitions.push({ input: inputPath, output: outputPath, steps: count });
    records.push({ input: [...inputBytes], output: [...outputBytes] });
  }
  const manifest = join(directory, 'invocations.json');
  await writeFile(manifest, JSON.stringify([{ name: 'execution', image: imagePath, transitions }]));
  const generated = await command('lake', ['exe', 'boundary-execution-producer', manifest, directory], formal, { quiet: true });
  if (generated.signal) fail(2, 'witness.tool_failure', `Candidate generation terminated: ${generated.signal}`);
  if (generated.code !== 0) {
    const rejected = !/inconclusive:/.test(generated.text) &&
      /malformed|candidate invocation rejected|differs from complete image|complete program admission rejected|invalid exact program subject|omitted a boundary state|initial execution must start|trailing initial argument/.test(generated.text);
    fail(rejected ? 1 : 2, rejected ? 'execution.rejected' : 'witness.inconclusive', generated.text.trim());
  }
  const metadata = (await readdir(directory)).filter((name) => /^BoundaryCertificateExecution[0-9a-f]{64}\.json$/.test(name));
  if (metadata.length !== 1) fail(2, 'proof.inventory', 'Candidate producer did not emit exactly one execution artifact');
  const certificate = JSON.parse(await readFile(join(directory, metadata[0]), 'utf8'));
  const expected = { name: `${certificate.module}.certificate`, kind: 'initial-execution', image: [...image], records };
  if (!/^BoundaryCertificateExecution[0-9a-f]{64}$/.test(certificate.module) ||
      certificate.status !== 'candidate' || certificate.case !== 'execution' ||
      certificate.path !== join(directory, `${certificate.module}.lean`) ||
      !isDeepStrictEqual(certificate.claims, [expected]))
    fail(2, 'proof.subject', 'Generated claim does not match the independently captured complete subject');
  let artifacts;
  try { artifacts = certificateClosure([certificate]); }
  catch (error) { fail(2, 'proof.inventory', error.message); }
  if (artifacts.some((artifact) => artifact.path !== join(directory, `${artifact.module}.lean`) ||
      (artifact.module !== certificate.module &&
        (!/^BoundaryCertificateImage[0-9a-f]{64}[A-Za-z0-9]*$/.test(artifact.module) || artifact.claims.length))))
    fail(2, 'proof.inventory', 'Generated proof dependency does not match the fixed artifact contract');
  const generatedFiles = (await readdir(directory)).filter((name) => name.endsWith('.lean')).sort();
  if (!isDeepStrictEqual(generatedFiles, artifacts.map((artifact) => `${artifact.module}.lean`).sort()))
    fail(2, 'proof.inventory', 'Generated proof files and the declared dependency inventory differ');
  let report;
  try { report = await checkCore(formal, { certificates: [certificate], quiet: true }); }
  catch (error) { fail(2, 'proof.inconclusive', error.message); }
  const proofArtifacts = [];
  for (const artifact of artifacts) {
    const bytes = await readFile(artifact.path), digest = sha256(bytes);
    if (report.modules.find((module) => module.name === artifact.module)?.sha256 !== digest)
      fail(2, 'proof.source_changed', 'A checked proof dependency changed before result publication');
    proofArtifacts.push({ module: artifact.module, source: artifact.path, source_sha256: digest, source_bytes: bytes.length });
  }
  return { certificate, report, proofArtifacts, records: records.length };
}

export async function main(args) {
  const started = performance.now();
  let selected;
  try { selected = options(args); }
  catch (error) { process.stderr.write(`${error.message}\n`); return error.exitCode ?? 64; }
  const result = { format: 'boundary.certification-result/v1', status: 'inconclusive',
    kind: selected.source ? 'program' : 'initial-execution', profile: 'boundary.v2',
    boundary: null, world: null, tools: [], subjects: [], exact_byte_binding: null,
    theorem: null, trust: null, kernel: null, replay: null, coverage: null, diagnostics: [] };
  let exitCode = 2;
  try {
    const output = join(await realpath(dirname(selected.output)), basename(selected.output));
    const inputs = [];
    for (const role of ['source', 'image', 'execution', 'witness']) {
      if (!selected[role]) continue;
      const path = await realpath(selected[role]);
      const inputName = join(await realpath(dirname(selected[role])), basename(selected[role]));
      if (path === output || inputName === output)
        fail(64, 'usage.output_alias', 'Output path must differ from every input path', role);
      const value = await readFile(path);
      inputs.push({ role, path: selected[role], bytes: value });
      result.subjects.push({ role, length: value.length, sha256: sha256(value) });
    }
    selected.output = output;
    // A killed or failed recheck must not leave a prior success at this path.
    await rm(output, { force: true });
    const snapshot = await sources();
    result.boundary = await boundaryIdentity(snapshot);
    result.tools = await toolIdentities();
    if (selected.source)
      fail(2, 'program.proof_rules_incomplete', 'Full-profile translation certification is not yet implemented; fragment theorems do not certify this program', 'source');
    await checkedCommand('lake', ['build', 'BoundaryV2', 'boundary-trust', 'boundary-execution-producer']);
    result.tools.push(await executable(join(formal, '.lake/build/bin/boundary-trust'), 'trust-auditor'));
    result.tools.push(await executable(join(formal, '.lake/build/bin/boundary-execution-producer'), 'candidate-producer'));
    const parent = join(formal, '.cache/certify');
    await mkdir(parent, { recursive: true });
    const directory = await mkdtemp(join(parent, 'run-'));
    const input = (role) => inputs.find((input) => input.role === role).bytes;
    const checked = await certifyExecution(input('execution'), input('witness'), input('image'), directory);
    await unchanged(inputs, snapshot, result.tools);
    result.status = 'certified';
    result.exact_byte_binding = true;
    result.proof_artifacts = checked.proofArtifacts;
    result.theorem = { name: checked.certificate.claims[0].name,
      ...checked.proofArtifacts.find((artifact) => artifact.module === checked.certificate.module) };
    result.trust = { status: 'passed', allowed_axioms: checked.report.allowed_axioms,
      modules: checked.report.modules.length, declarations: checked.report.declaration_count };
    result.kernel = { status: 'passed', ordinary_proof: true };
    result.replay = { status: 'passed', fresh: true };
    result.coverage = { completed_invocations: checked.records, initial_execution: true, full_program: false };
    exitCode = 0;
  } catch (error) {
    exitCode = error.exitCode ?? 2;
    result.status = exitCode === 1 ? 'rejected' : 'inconclusive';
    result.diagnostics.push({ code: error.code ?? 'tool.failure', role: error.role ?? null, message: error.message });
  }
  result.elapsed_ms = Math.round(performance.now() - started);
  if (exitCode === 64) { process.stderr.write(`${result.diagnostics[0].message}\n`); return 64; }
  try { await atomicResult(selected.output, result); }
  catch (error) { process.stderr.write(`result.write: ${error.message}\n`); return 2; }
  process.stderr.write(`${result.status}: ${result.diagnostics[0]?.message ?? result.theorem.name}\n`);
  return exitCode;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href)
  process.exitCode = await main(process.argv.slice(2));
