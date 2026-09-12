// Ordinary source/compiler/native/WASM conformance. No proof certificates.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import { parseExactJson } from '../../tools/v2/exact_json.mjs';
import { execute } from './source_oracle.mjs';
import { cases } from './semantic_cases.mjs';

const { values } = parseArgs({ options: {
  world: { type: 'string' }, fixtures: { type: 'string', default: 'zig-out' },
  case: { type: 'string' },
} });
assert.ok(values.world, 'usage: node test/v2/conformance.mjs --world <pinned-checkout> [--fixtures <directory>] [--case <name>]');
const boundary = resolve(import.meta.dirname, '../..'), world = resolve(values.world);
const fixtures = resolve(values.fixtures), output = join(boundary, '.cache/v2/conformance');
const worldRevision = '87698f92ca7be4d5442e97ba27a2468aa3ff6a7c';
function run(command, args, cwd = boundary, options = {}) {
  const result = spawnSync(command, args, { cwd, encoding: 'utf8', maxBuffer: 64 << 20, ...options });
  assert.ifError(result.error);
  assert.equal(result.signal, null, `${command} terminated: ${result.signal}`);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout;
}
assert.equal(run('git', ['rev-parse', 'HEAD'], world).trim(), worldRevision, 'World checkout does not match the pinned test dependency');
assert.equal(run('git', ['status', '--porcelain', '--untracked-files=no'], world).trim(), '', 'World tracked sources must be unmodified');
assert.equal(run('zig', ['version']).trim(), '0.16.0');
const boundaryRevision = run('git', ['rev-parse', 'HEAD']).trim();
const boundaryDirty = run('git', ['status', '--porcelain']).trim() ? ' (working tree changes)' : '';
console.log(`conformance inputs: Boundary ${boundaryRevision}${boundaryDirty}, World ${worldRevision}, Zig 0.16.0, Node ${process.version}`);
await mkdir(output, { recursive: true });
const native = join(output, 'world-native');
run('zig', ['build-exe', '-O', 'ReleaseSafe', '--dep', 'world', '--dep', 'boundary_data_v2',
  `-Mroot=${join(world, 'test/v2/native_records.zig')}`, '-O', 'ReleaseSafe', '--dep', 'boundary_data_v2',
  `-Mworld=${join(world, 'src/root.zig')}`, '-O', 'ReleaseSafe', `-Mboundary_data_v2=${join(boundary, 'src/v2/data/root.zig')}`,
  `-femit-bin=${native}`]);
run('zig', ['build', 'build-v2-kernel', `-Dboundary-v2-source=${boundary}`, '--prefix', output, '-j2'], world);
const kernel = await readFile(join(output, 'world-process-kernel-v2.wasm'));
const kernelHash = createHash('sha256').update(kernel).digest('hex');
const { admitProcessKernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } =
  await import(pathToFileURL(join(world, 'src/process_v2/index.mjs')));
let invocations = 0, checks = 0, currentCase;
async function compare(mode, input, rejection = false) {
  const bytes = encodeInput({ ...input, mode });
  const nativeResult = spawnSync(native, [], { input: bytes, maxBuffer: 64 << 20, timeout: 120000 });
  assert.ifError(nativeResult.error);
  assert.equal(nativeResult.signal, null, 'native execution terminated by a signal');
  const host = await admitProcessKernel(kernel, { expectedSha256: kernelHash });
  if (rejection) {
    assert.notEqual(nativeResult.status, 0, 'native accepted a mismatched response');
    assert.match(nativeResult.stderr.toString(), /InvalidResult/, 'native rejection had an unexpected cause');
    await assert.rejects(host[mode](input), /InvalidResult/);
    return;
  }
  let wasm;
  try { wasm = await host[mode](input); }
  catch (error) {
    await writeFile(join(output, 'failure.input'), bytes);
    throw new Error(currentCase + ': native=' + nativeResult.stderr.toString().trim() + '; wasm=' + error.message, { cause: error });
  }
  assert.equal(nativeResult.status, 0, currentCase + ': ' + nativeResult.stderr.toString());
  assert.deepEqual(Buffer.from(wasm.bytes), nativeResult.stdout, 'native/WASM complete outcome differs');
  const selected = invocations++ % 2 ? nativeResult.stdout : wasm.bytes;
  return { ...decodeOutcome(selected), bytes: new Uint8Array(selected) };
}
const terminal = new Set(['Completed', 'Failed', 'Cancelled']);
const selected = values.case ? cases.filter(test => test.name === values.case) : cases;
assert.ok(selected.length, 'no matching conformance case');
for (const test of selected) {
  currentCase = test.name;
  const source = parseExactJson(await readFile(join(fixtures, `source-${test.program}.json`)));
  const image = new Uint8Array(await readFile(join(fixtures, `source-${test.program}.bpi2`)));
  const expected = execute(source, test.initial, test.responses, test.cancellations);
  const trace = [], applied = new Set();
  let responseIndex = 0, state = await compare('run', { image, initialArgs: Uint8Array.from(test.initial) });
  for (let boundaryIndex = 0; !terminal.has(state.kind); boundaryIndex++) {
    assert.ok(boundaryIndex < 10000, `${test.name}: unfinished at test horizon`);
    if (state.kind === 'Progressed') { state = await compare('run', { image, state: state.state }); continue; }
    if (state.kind === 'Requested') {
      const request = decodeRequest(state.request);
      trace.push({ kind: 'Requested', identity: request.semanticIdentity, payload: [...request.payload] });
      const polled = await compare('run', { image, state: state.state });
      assert.deepEqual(polled.bytes, state.bytes, 'parked polling changed the logical request');
    } else {
      assert.equal(state.kind, 'Yielded');
      trace.push({ kind: 'Yielded' });
    }
    const controls = test.cancellations.map((control, index) => ({ ...control, index }))
      .filter(control => control.at === trace.length - 1 && !applied.has(control.index));
    let leftBoundary = false;
    for (const [index, control] of controls.entries()) {
      const prior = state;
      const mode = !control.preservesRequest && index + 1 < controls.length ? 'advance' : 'run';
      state = await compare(mode, { image, state: state.state, cancel: control.reason });
      applied.add(control.index);
      if (control.preservesRequest) {
        assert.equal(state.kind, 'Requested', 'cancellation lost the pending cleanup request');
        assert.deepEqual(decodeRequest(state.request).payload, decodeRequest(prior.request).payload);
      } else leftBoundary = true;
    }
    if (leftBoundary) continue;
    if (state.kind === 'Requested') {
      if (responseIndex === test.responses.length) break;
      const result = encodeResult(state.request, Uint8Array.from(test.responses[responseIndex++]));
      if (checks === 0 && result.length > 20) {
        const invalid = result.slice(); invalid[20] ^= 1;
        await compare('run', { image, state: state.state, result: invalid }, true);
        const unchanged = await compare('run', { image, state: state.state });
        assert.deepEqual(unchanged.bytes, state.bytes, 'rejected response consumed the future');
        checks++;
      }
      state = await compare('run', { image, state: state.state, result });
    } else state = await compare('run', { image, state: state.state });
  }
  const actual = { trace, kind: state.kind };
  if (state.kind === 'Completed' || state.kind === 'Failed') actual.value = [...state.value];
  if (state.kind === 'Failed' || state.kind === 'Cancelled') actual.cleanupFailures = state.cleanupFailures.map(value => [...value]);
  if (state.kind === 'Failed' && state.cancellation !== null && state.cancellation !== undefined) actual.cancellation = state.cancellation;
  if (state.kind === 'Cancelled') actual.reason = state.reason;
  assert.equal(responseIndex, test.responses.length, `${test.name}: unused responses`);
  assert.equal(applied.size, test.cancellations.length, `${test.name}: unused cancellation`);
  assert.deepEqual(actual, expected, `${test.name}: runtime differs from independent source semantics`);
  console.log(`conformance: ${test.name} passed`);
}
console.log(`conformance: ${selected.length} cases, ${invocations} fresh native/WASM comparisons; Boundary ${boundaryRevision}${boundaryDirty}, World ${worldRevision}, Zig 0.16.0, Node ${process.version}`);
