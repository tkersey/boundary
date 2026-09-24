// Transfer the migrated recursive image's actual State between the fixed
// Node package and the selected World source's locked Wasmtime ABI 3 peer.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [bundle, imagePath, sha256, nativePath, worldSource] = process.argv.slice(2);
if (!bundle || !imagePath || !sha256 || !nativePath || !worldSource)
  throw new Error('usage: node authoring_wasmtime.mjs BUNDLE IMAGE SHA NATIVE WORLD_SOURCE');
const { Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } =
  await import(pathToFileURL(join(bundle, 'runtime/src/embedding/index.mjs')).href);
const { wasmtimePeer } = await import(pathToFileURL(join(worldSource,
  'test/current/peer.mjs')).href);
const kernelPath = join(bundle, 'runtime/world-kernel.wasm');
const image = readFileSync(imagePath);
const kernel = await Kernel.create({ bytes: readFileSync(kernelPath), expectedSha256: sha256 });
const peer = await wasmtimePeer(kernelPath, sha256);
const word = n => { const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setBigUint64(0, BigInt(n), true); return bytes; };
const native = input => {
  const result = spawnSync(nativePath, ['invoke'], { input, timeout: 30000 });
  assert.equal(result.status, 0, result.stderr.toString());
  return new Uint8Array(result.stdout);
};
try {
  const initial = encodeInput({ image, initialArgs: new Uint8Array() });
  const nodeStart = kernel.invoke(initial);
  const wasmStart = (await peer.call('invoke', { bytes: initial })).bytes;
  assert.deepEqual(nodeStart, wasmStart);
  assert.deepEqual(nodeStart, native(initial));
  const requested = decodeOutcome(wasmStart);
  assert.equal(requested.kind, 'requested');
  const request = await decodeRequest(requested.request);
  assert.equal(request.semanticIdentity, 'hyper/reference');
  assert.deepEqual(request.payload, word(19));
  for (const reply of [19, 20]) {
    const command = encodeInput({ image, state: requested.state, control: 'reply',
      value: await encodeResult(requested.request, word(reply)) });
    const nodeResult = kernel.invoke(command);
    const wasmResult = (await peer.call('invoke', { bytes: command })).bytes;
    assert.deepEqual(nodeResult, wasmResult);
    assert.deepEqual(nodeResult, native(command));
    const terminal = decodeOutcome(nodeResult);
    assert.equal(terminal.kind, 'completed');
    assert.deepEqual(terminal.value, word(reply + 23));
  }
  console.log(JSON.stringify({ check: 'migrated recursive Node/Wasmtime/native State transfer',
    replies: [19, 20], results: [42, 43], wasmtime: peer.identity.wasmtime,
    python: peer.identity.python }));
} finally {
  await peer.close();
}
