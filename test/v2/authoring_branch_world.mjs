import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [bundle, imagePath, sha256, nativePath] = process.argv.slice(2);
if (!bundle || !imagePath || !sha256 || !nativePath)
  throw new Error('usage: node authoring_branch_world.mjs BUNDLE IMAGE SHA NATIVE');
const { Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } =
  await import(pathToFileURL(join(bundle, 'runtime/src/embedding/index.mjs')).href);
const image = readFileSync(imagePath);
const word = n => { const bytes = new Uint8Array(4);
  new DataView(bytes.buffer).setUint32(0, n, true); return bytes; };
for (const enabled of [false, true]) {
  const kernel = await Kernel.create({ bytes: readFileSync(join(bundle,
    'runtime/world-kernel.wasm')), expectedSha256: sha256 });
  const invoke = input => { const wasm = kernel.invoke(input);
    const native = spawnSync(nativePath, ['invoke'], { input, timeout: 30000 });
    assert.equal(native.status, 0, native.stderr.toString());
    assert.deepEqual(wasm, new Uint8Array(native.stdout));
    return decodeOutcome(wasm); };
  let outcome = invoke(encodeInput({ image,
    initialArgs: new Uint8Array([enabled ? 1 : 0, ...word(7)]) }));
  const requests = [];
  if (enabled) {
    assert.equal(outcome.kind, 'requested');
    const request = await decodeRequest(outcome.request);
    assert.equal(request.semanticIdentity, 'authoring/lookup');
    assert.deepEqual(request.payload, word(7));
    requests.push(request.semanticIdentity);
    outcome = invoke(encodeInput({ image, state: outcome.state, control: 'reply',
      value: await encodeResult(outcome.request, word(19)) }));
  }
  assert.equal(outcome.kind, 'completed');
  assert.deepEqual(outcome.value, word(enabled ? 19 : 7));
  assert.deepEqual(requests, enabled ? ['authoring/lookup'] : []);
}
console.log(JSON.stringify({ falseBranch: { result: 7, requests: 0 },
  trueBranch: { result: 19, requests: 1 }, nativeAgreement: true }));
