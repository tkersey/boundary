import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { link, mkdir, mkdtemp, readFile, symlink, writeFile } from 'node:fs/promises';
import { delimiter, dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [formalArgument, worldArgument, capacityArgument, ...extra] = process.argv.slice(2);
assert.ok(formalArgument && worldArgument && capacityArgument && !extra.length,
  'usage: certification_cli.mjs <formal-root> <world-root> <captured-capacity-directory>');
const formal = resolve(formalArgument), world = resolve(worldArgument), capacity = resolve(capacityArgument);
const { admitProcessKernel, encodeInput, encodeResult } = await import(
  pathToFileURL(join(world, 'src/process_v2/index.mjs')).href);
const image = await readFile(join(capacity, 'capacity.bpi2'));
const wasm = await readFile(join(capacity, 'normal.wasm'));
const kernel = await admitProcessKernel(wasm, {
  expectedSha256: createHash('sha256').update(wasm).digest('hex'),
});
const args = new Uint8Array([3, 17, 29, 43]);
const first = { image, initialArgs: args, mode: 'run' };
const requested = await kernel.run(first);
assert.equal(requested.kind, 'Requested');
const second = { image, state: requested.state, result: encodeResult(requested.request, new Uint8Array()), mode: 'run' };
const completed = await kernel.run(second);
assert.equal(completed.kind, 'Completed');
assert.deepEqual(completed.value, args);
const execution = { format: 'boundary.execution-segment/v1', completion: 'complete', records: [
  { input: [...encodeInput(first)], output: [...requested.bytes] },
  { input: [...encodeInput(second)], output: [...completed.bytes] },
] };
const witness = { format: 'boundary.execution-witness/v1', image_bytes: [...image],
  borrow: JSON.parse(await readFile(join(capacity, 'capacity.bpi2.graph.borrow.json'))), steps: [1, 1] };
const parent = join(formal, '.cache/certification-cli');
await mkdir(parent, { recursive: true });
const directory = await mkdtemp(join(parent, 'run-'));
const paths = Object.fromEntries(['image', 'execution', 'witness', 'output'].map((role) => [role, join(directory, role)]));
await writeFile(paths.image, image);
const originalExecution = Buffer.from(JSON.stringify(execution)), originalWitness = Buffer.from(JSON.stringify(witness));
await writeFile(paths.execution, originalExecution); await writeFile(paths.witness, originalWitness);
function invoke(changed = {}) {
  const inputs = { ...paths, ...changed };
  const parameters = Object.entries(inputs).flatMap(([role, path]) => [`--${role}`, path]);
  const run = spawnSync('lake', ['exe', 'boundary-certify',
    ...parameters], { cwd: formal, env: { ...process.env, PATH: `${dirname(process.execPath)}${delimiter}${process.env.PATH}` },
    encoding: 'utf8', maxBuffer: 1024 * 1024 });
  assert.equal(run.signal, null, run.stderr);
  assert.equal(run.error, undefined);
  return run;
}
async function result(expectedCode, expectedStatus) {
  const run = invoke();
  assert.equal(run.status, expectedCode, run.stderr);
  const output = JSON.parse(await readFile(paths.output));
  assert.equal(output.format, 'boundary.certification-result/v1');
  assert.equal(output.status, expectedStatus);
  assert.equal(output.exact_byte_binding, null);
  assert.equal(output.kernel, null);
  assert.equal(output.replay, null);
  return output;
}
await writeFile(paths.execution, '{"format":"boundary.execution-segment/v1","format":"duplicate"}');
assert.equal((await result(1, 'rejected')).diagnostics[0].code, 'input.json');
const changed = structuredClone(execution); changed.records[1].output[0] ^= 1;
await writeFile(paths.execution, JSON.stringify(changed));
assert.equal((await result(1, 'rejected')).diagnostics[0].code, 'execution.rejected');
await writeFile(paths.execution, JSON.stringify({ ...execution, records: execution.records.slice(0, 1) }));
await writeFile(paths.witness, JSON.stringify({ ...witness, steps: [1] }));
assert.equal((await result(2, 'inconclusive')).diagnostics[0].code, 'witness.inconclusive');
await writeFile(paths.execution, originalExecution); await writeFile(paths.witness, originalWitness);
assert.equal(invoke({ output: paths.execution }).status, 64);
assert.deepEqual(await readFile(paths.execution), originalExecution);
const alias = join(directory, 'execution-alias'); await symlink(paths.execution, alias);
assert.equal(invoke({ execution: alias, output: alias }).status, 64);
assert.deepEqual(await readFile(alias), originalExecution);
assert.deepEqual(await readFile(paths.execution), originalExecution);

// Publishing a result over another name for an input inode must preserve the
// input and replace the destination with a separate, fully checked result.
const hardlink = join(directory, 'hardlinked-result'); await link(paths.witness, hardlink);
const run = invoke({ output: hardlink });
assert.equal(run.status, 0, run.stderr);
const certified = JSON.parse(await readFile(hardlink));
assert.equal(certified.status, 'certified');
assert.equal(certified.exact_byte_binding, true);
assert.ok(certified.proof_artifacts.length > 1);
assert.equal(new Set(certified.proof_artifacts.map((artifact) => artifact.module)).size, certified.proof_artifacts.length);
for (const artifact of certified.proof_artifacts) {
  const bytes = await readFile(artifact.source);
  assert.equal(bytes.length, artifact.source_bytes);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), artifact.source_sha256);
}
assert.deepEqual(certified.theorem, { name: certified.theorem.name,
  ...certified.proof_artifacts.find((artifact) => artifact.module === certified.theorem.module) });
assert.deepEqual(certified.kernel, { status: 'passed', ordinary_proof: true });
assert.deepEqual(certified.replay, { status: 'passed', fresh: true });
assert.deepEqual(certified.coverage, { completed_invocations: 2, initial_execution: true, full_program: false });
assert.deepEqual(certified.tools.map((tool) => tool.role), ['node', 'lean', 'leanchecker', 'trust-auditor', 'candidate-producer']);
assert.deepEqual(await readFile(paths.witness), originalWitness);
assert.deepEqual(await readFile(paths.execution), originalExecution);
assert.deepEqual(await readFile(paths.image), image);
for (const subject of certified.subjects) {
  const original = subject.role === 'image' ? image : subject.role === 'execution' ? originalExecution : originalWitness;
  assert.equal(subject.length, original.length);
  assert.equal(subject.sha256, createHash('sha256').update(original).digest('hex'));
}
// A subsequent failed recheck replaces the old acceptance at that same path.
await writeFile(paths.execution, JSON.stringify(changed));
assert.equal(invoke({ output: hardlink }).status, 1);
assert.equal(JSON.parse(await readFile(hardlink)).status, 'rejected');
console.log('certification CLI: complete World execution, exact subjects, ordinary proof/fresh replay, refusal and atomic output checks passed');
