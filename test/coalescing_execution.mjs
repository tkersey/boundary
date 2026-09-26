// Same authenticated runtime and independent expected values for both image arms.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const [emitter, runtime, expectedSha256, native, ...componentImages] = process.argv.slice(2);
const trees = componentImages.length===1 && componentImages[0]==='trees';
const edges = componentImages.length===1 && componentImages[0]==='edges';
assert.ok(emitter && runtime && /^[a-f0-9]{64}$/.test(expectedSha256 ?? '') && native,
  'usage: node test/coalescing_execution.mjs EMITTER RUNTIME SHA256 NATIVE');
const {Kernel, encodeInput, decodeOutcome} =
  await import(pathToFileURL(resolve(runtime, 'src/embedding/index.mjs')));
const kernelBytes = new Uint8Array(await readFile(resolve(runtime, 'world-kernel.wasm')));
const wasmtime = process.env.WORLD_WASMTIME_PEER
  ? await (await import(pathToFileURL(resolve(process.env.WORLD_WASMTIME_PEER))))
      .wasmtimePeer(resolve(runtime,'world-kernel.wasm'),expectedSha256) : null;
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
    if(wasmtime)assert.deepEqual((await wasmtime.call('invoke',{bytes:input})).bytes,encoded,
      'Wasmtime envelope disagreement');
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

try {
const measurements = [];
for (const count of componentImages.length ? [] : [1, 2, 16, 64, 256]) {
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
    assert.throws(() => foreign.invoke(encodeInput({image: safe.image, state: suspended.state, quantum: 1})),
      error => error.code === 'WORLD_KERNEL_REJECTED' && error.details?.diagnostic === 'InvalidState');
  }
  measurements.push({count, off: off.statistics, safe: safe.statistics});
}
if (trees) {
  for(const kind of ['tree','tree_near']) {
    const off=emit('off',kind), safe=emit('safe',kind);
    assert.equal(off.statistics.functions,19);
    assert.equal(safe.statistics.functions,kind==='tree'?10:19);
    assert.equal(off.statistics.constructors,8);
    assert.equal(safe.statistics.constructors,kind==='tree'?4:8);
    assert.ok(safe.image.length<=off.image.length);
    if(kind==='tree')assert.ok(safe.image.length<off.image.length);
    const baseline=await execute(off.image,words([10]),1);
    assert.deepEqual(await execute(safe.image,words([10]),1),baseline);
    assert.equal(baseline.kind,'completed');
    assert.equal(baseline.value,Buffer.from(words([18,kind==='tree'?18:19])).toString('hex'));
    const failure=await execute(off.image,words([(1n<<64n)-1n]),1);
    assert.equal(failure.kind,'failed');
    assert.deepEqual(await execute(safe.image,words([(1n<<64n)-1n]),1),failure);
    measurements.push({kind,off:off.statistics,safe:safe.statistics,
      normal:baseline,overflow:failure});
  }
} else if (edges) {
  for(const kind of ['swap','cycle']) {
    const off=emit('off',kind), safe=emit('safe',kind);
    assert.equal(off.statistics.functions,3);
    assert.equal(safe.statistics.functions,2);
    assert.ok(safe.image.length<off.image.length);
    const input=words([11,22,33]);
    const baseline=await execute(off.image,input,1);
    assert.deepEqual(await execute(safe.image,input,1),baseline);
    const triple=kind==='swap'?[22,11,33]:[22,33,11];
    assert.equal(baseline.value,Buffer.from(words([...triple,...triple])).toString('hex'));
    measurements.push({kind,off:off.statistics,safe:safe.statistics,observation:baseline});
  }
} else if (componentImages.length) {
  assert.equal(componentImages.length, 2);
  const images = await Promise.all(componentImages.map(async path => new Uint8Array(await readFile(path))));
  const off = await execute(images[0], new Uint8Array(), 1);
  const safe = await execute(images[1], new Uint8Array(), 1);
  assert.deepEqual(safe, off);
  assert.equal(safe.kind, 'completed');
  assert.equal(safe.value, Buffer.from(words([13, 17])).toString('hex'));
  measurements.push({case: 'source-free components', observation: safe});
}
console.log(JSON.stringify({check: edges ? 'coalescing simultaneous assignments and slot reuse'
  : trees ? 'coalescing depth-eight reference-induced sharing'
  : componentImages.length
  ? 'coalescing source-free components native/WASM and fresh-host resume'
  : 'coalescing captured closures native/WASM and fresh-host resume',
  runtimeSha256: expectedSha256, wasmtime:wasmtime?.identity??{status:'NOT_RUN'}, measurements}));
} finally {if(wasmtime)await wasmtime.close();}
