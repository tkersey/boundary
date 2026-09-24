// Compare the fixed native runner with fresh Node/WASM processes at a real
// reciprocal-demand request boundary. Each restored reply starts a new process.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const [mode, bundle, imagePath, kernelSha256, nativePath, ...rest] = process.argv.slice(2);
if (!mode || !bundle || !imagePath || !kernelSha256 || !nativePath)
  throw new Error('usage: node hyper_demand_world.mjs main BUNDLE IMAGE SHA NATIVE');
const { Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } =
  await import(pathToFileURL(join(bundle, 'runtime/src/embedding/index.mjs')).href);
const image = readFileSync(imagePath);
const word = number => {
  const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setBigUint64(0, BigInt(number), true);
  return bytes;
};

async function invoke(input) {
  const kernel = await Kernel.create({ bytes: readFileSync(join(bundle,
    'runtime/world-kernel.wasm')), expectedSha256: kernelSha256 });
  const wasm = kernel.invoke(input);
  const native = spawnSync(nativePath, ['invoke'], { input,
    maxBuffer: 8 << 20, timeout: 30000 });
  assert.equal(native.status, 0, native.stderr.toString());
  assert.deepEqual(new Uint8Array(native.stdout), wasm);
  return decodeOutcome(wasm);
}

if (mode === 'stage') {
  const [action, state64, request64, reply] = rest;
  if (action === 'start') {
    const outcome = await invoke(encodeInput({ image, initialArgs: new Uint8Array() }));
    assert.equal(outcome.kind, 'requested');
    const request = await decodeRequest(outcome.request);
    assert.equal(request.semanticIdentity, 'hyper/reference');
    assert.deepEqual(request.payload, word(19));
    console.log(JSON.stringify({ kind: outcome.kind,
      state: Buffer.from(outcome.state).toString('base64'),
      request: Buffer.from(outcome.request).toString('base64'),
      stateBytes: outcome.state.length }));
  } else if (action === 'restore') {
    const state = Buffer.from(state64, 'base64');
    const request = Buffer.from(request64, 'base64');
    const outcome = await invoke(encodeInput({ image, state, control: 'reply',
      value: await encodeResult(request, word(reply)) }));
    assert.ok(outcome.kind === 'completed' || outcome.kind === 'failed');
    console.log(JSON.stringify({ kind: outcome.kind,
      value: Buffer.from(outcome.value).toString('hex') }));
  } else throw new Error('invalid stage action');
} else if (mode === 'main') {
  const script = fileURLToPath(import.meta.url);
  const stage = args => JSON.parse(execFileSync(process.execPath,
    [script, 'stage', bundle, imagePath, kernelSha256, nativePath, ...args],
    { encoding: 'utf8', timeout: 30000, maxBuffer: 8 << 20 }));
  const parked = stage(['start']);
  const outcomes = [19n, 20n, 18446744073709551615n].map(reply =>
    stage(['restore', parked.state, parked.request, reply.toString()]));
  assert.deepEqual(outcomes, [
    { kind: 'completed', value: '2a00000000000000' },
    { kind: 'completed', value: '2b00000000000000' },
    { kind: 'failed', value: '' },
  ]);
  console.log(JSON.stringify({ request: 'hyper/reference', payload: 19,
    replies: [19, 20, 'max-u64'], results: [42, 43, 'failed'],
    stateBytes: parked.stateBytes, freshProcesses: true, nativeAgreement: true }));
} else throw new Error('invalid mode');
