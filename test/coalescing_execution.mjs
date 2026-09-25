// Same authenticated runtime and independent expected values for both image arms.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const [emitter, runtime, expectedSha256, native] = process.argv.slice(2);
assert.ok(emitter && runtime && /^[a-f0-9]{64}$/.test(expectedSha256 ?? '') && native,
  'usage: node test/coalescing_execution.mjs EMITTER RUNTIME SHA256 NATIVE');
const {Kernel, encodeInput, decodeOutcome} =
  await import(pathToFileURL(resolve(runtime, 'src/embedding/index.mjs')));
const kernelBytes = new Uint8Array(await readFile(resolve(runtime, 'world-kernel.wasm')));
const words = values => {
  const bytes = new Uint8Array(8 * values.length), view = new DataView(bytes.buffer);
  values.forEach((value, i) => view.setBigUint64(i * 8, BigInt(value), true));
  return bytes;
};
function emit(mode, count) {
  const process = spawnSync(emitter, [mode, String(count)], {maxBuffer: 16 << 20});
  assert.equal(process.status, 0, process.stderr.toString());
  return {image: new Uint8Array(process.stdout), statistics: JSON.parse(process.stderr)};
}
async function fresh() {
  const kernel = await Kernel.create({bytes: kernelBytes, expectedSha256});
  kernel.setLimits({input: 2 << 20, working: 8 << 20, output: 2 << 20});
  return kernel;
}
async function execute(image, initialArgs, quantum = null) {
  let state;
  const trace = [];
  for (let step = 0; step < 4096; step++) {
    const input = encodeInput({image, initialArgs: state ? undefined : initialArgs, state, quantum});
    const kernel = await fresh();
    const encoded = kernel.invoke(input);
    const peer = spawnSync(native, ['invoke'], {input, maxBuffer: 16 << 20});
    assert.equal(peer.status, 0, peer.stderr.toString());
    assert.deepEqual(encoded, new Uint8Array(peer.stdout), 'native/WASM envelope disagreement');
    const outcome = decodeOutcome(encoded);
    trace.push(outcome.kind);
    if (outcome.kind === 'completed' || outcome.kind === 'failed') {
      if (outcome.kind === 'failed') assert.deepEqual(outcome.cleanupFailures, []);
      return {kind: outcome.kind, value: Buffer.from(outcome.value).toString('hex'), trace};
    }
    assert.equal(outcome.kind, 'progressed');
    assert.ok(outcome.state?.length);
    state = outcome.state; // Each next operation restores on a fresh runtime instance.
  }
  throw Error('finite observation bound exceeded');
}

const measurements = [];
for (const count of [1, 2, 16, 64, 256]) {
  const off = emit('off', count), safe = emit('safe', count);
  assert.equal(safe.statistics.functions, 2);
  assert.equal(safe.statistics.constructors, 1);
  assert.equal(safe.statistics.captures, 1);
  assert.ok(safe.image.length <= off.image.length);
  if (count >= 16) assert.ok(safe.image.length < off.image.length);
  const captures = Array.from({length: count}, (_, i) => 3n + 4n * BigInt(i));
  const input = words(captures), expected = Buffer.from(words(captures.map(v => v + 10n))).toString('hex');
  const baseline = await execute(off.image, input), selected = await execute(safe.image, input);
  assert.deepEqual(selected, baseline);
  assert.equal(selected.kind, 'completed');
  assert.equal(selected.value, expected);
  if (count === 2) {
    const stepped = await execute(off.image, input, 1);
    assert.deepEqual(await execute(safe.image, input, 1), stepped);
    const overflow = words([(1n << 64n) - 1n, 7n]);
    const failure = await execute(off.image, overflow, 1);
    assert.equal(failure.kind, 'failed');
    assert.equal(failure.value, '');
    assert.deepEqual(await execute(safe.image, overflow, 1), failure);
    const original = await fresh();
    const suspended = decodeOutcome(original.invoke(encodeInput({image: off.image, initialArgs: input, quantum: 1})));
    assert.ok(suspended.state?.length);
    const foreign = await fresh();
    assert.throws(() => foreign.invoke(encodeInput({image: safe.image, state: suspended.state, quantum: 1})));
  }
  measurements.push({count, off: off.statistics, safe: safe.statistics});
}
console.log(JSON.stringify({check: 'coalescing captured closures native/WASM and fresh-host resume',
  runtimeSha256: expectedSha256, measurements}));
