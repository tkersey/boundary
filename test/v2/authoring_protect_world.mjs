import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [bundle, imagePath, sha256, nativePath] = process.argv.slice(2);
if (!bundle || !imagePath || !sha256 || !nativePath)
  throw new Error('usage: node authoring_protect_world.mjs BUNDLE IMAGE SHA NATIVE');
const { Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } =
  await import(pathToFileURL(join(bundle, 'runtime/src/embedding/index.mjs')).href);
const image = readFileSync(imagePath);
const word = n => { const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setBigUint64(0, BigInt(n), true); return bytes; };
async function invoke(input) {
  const kernel = await Kernel.create({ bytes: readFileSync(join(bundle,
    'runtime/world-kernel.wasm')), expectedSha256: sha256 });
  const wasm = kernel.invoke(input);
  const native = spawnSync(nativePath, ['invoke'], { input, timeout: 30000 });
  assert.equal(native.status, 0, native.stderr.toString());
  assert.deepEqual(wasm, new Uint8Array(native.stdout));
  return decodeOutcome(wasm);
}
let outcome = await invoke(encodeInput({ image, initialArgs: new Uint8Array() }));
const trace = [];
for (const [identity, reply] of [
  ['authoring/protect/read', word(41)],
  ['authoring/protect/release', new Uint8Array()],
]) {
  assert.equal(outcome.kind, 'requested');
  const request = await decodeRequest(outcome.request);
  assert.equal(request.semanticIdentity, identity);
  trace.push({ identity, payload: Buffer.from(request.payload).toString('hex') });
  outcome = await invoke(encodeInput({ image, state: outcome.state,
    control: 'reply', value: await encodeResult(outcome.request, reply) }));
}
assert.equal(outcome.kind, 'completed');
assert.deepEqual(outcome.value, word(41));
assert.deepEqual(trace, [
  { identity: 'authoring/protect/read', payload: '' },
  { identity: 'authoring/protect/release', payload: '0700000000000000' },
]);
console.log(JSON.stringify({ trace, result: 41, freshInstances: true,
  nativeAgreement: true }));
