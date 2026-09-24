import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [bundle, imagePath, sha256, nativePath] = process.argv.slice(2);
if (!bundle || !imagePath || !sha256 || !nativePath)
  throw new Error('usage: node authoring_twice_world.mjs BUNDLE IMAGE SHA NATIVE');
const { Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } =
  await import(pathToFileURL(join(bundle, 'runtime/src/embedding/index.mjs')).href);
const image = readFileSync(imagePath);
const kernel = await Kernel.create({ bytes: readFileSync(join(bundle,
  'runtime/world-kernel.wasm')), expectedSha256: sha256 });
const word = n => { const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setBigUint64(0, BigInt(n), true); return bytes; };
const invoke = input => {
  const wasm = kernel.invoke(input);
  const native = spawnSync(nativePath, ['invoke'], { input, timeout: 30000 });
  assert.equal(native.status, 0, native.stderr.toString());
  assert.deepEqual(wasm, new Uint8Array(native.stdout));
  return decodeOutcome(wasm);
};
let outcome = invoke(encodeInput({ image, initialArgs: new Uint8Array() }));
const requests = [];
for (const reply of [19, 23]) {
  assert.equal(outcome.kind, 'requested');
  const request = await decodeRequest(outcome.request);
  assert.equal(request.semanticIdentity, 'twice/lookup');
  assert.deepEqual(request.payload, word(5));
  requests.push(request.semanticIdentity);
  outcome = invoke(encodeInput({ image, state: outcome.state,
    control: 'reply', value: await encodeResult(outcome.request, word(reply)) }));
}
assert.equal(outcome.kind, 'completed');
assert.deepEqual(outcome.value, new Uint8Array([...word(19), ...word(23)]));
console.log(JSON.stringify({ requests, replies: [19, 23],
  result: [19, 23], nativeAgreement: true }));
