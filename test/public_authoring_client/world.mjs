import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [bundle, imagePath, kernelSha256, nativePath] = process.argv.slice(2);
if (!bundle || !imagePath || !kernelSha256) {
  throw new Error('usage: node world.mjs BUNDLE IMAGE KERNEL_SHA256');
}
const { Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } =
  await import(pathToFileURL(join(bundle, 'runtime/src/embedding/index.mjs')).href);
const image = readFileSync(imagePath);
const word = value => {
  const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setBigUint64(0, BigInt(value), true);
  return bytes;
};
const kernel = async () => Kernel.create({
  bytes: readFileSync(join(bundle, 'runtime/world-kernel.wasm')),
  expectedSha256: kernelSha256,
});
const invoke = (instance, inputBytes) => {
  const wasm = instance.invoke(inputBytes);
  if (nativePath) {
    const native = spawnSync(nativePath, ['invoke'], { input: inputBytes,
      maxBuffer: 8 << 20, timeout: 30000 });
    assert.equal(native.status, 0, native.stderr.toString());
    assert.deepEqual(new Uint8Array(native.stdout), wasm);
  }
  return decodeOutcome(wasm);
};
const input = (enabled, number, offset) => new Uint8Array([
  enabled ? 1 : 0, ...word(number), ...word(offset),
]);

async function run(enabled, number, offset, replies) {
  const k = await kernel();
  let outcome = invoke(k, encodeInput({ image,
    initialArgs: input(enabled, number, offset) }));
  const requests = [];
  for (let index = 0; index < 8 && outcome.kind === 'requested'; index++) {
    const request = await decodeRequest(outcome.request);
    requests.push({ identity: request.semanticIdentity,
      payload: Buffer.from(request.payload).toString('hex') });
    assert.ok(index < replies.length, 'unexpected extra request');
    outcome = invoke(k, encodeInput({ image, state: outcome.state,
      control: 'reply', value: await encodeResult(outcome.request, word(replies[index])) }));
  }
  return { outcome, requests };
}

const pure = await run(false, 7, 3, []);
assert.equal(pure.outcome.kind, 'completed');
assert.deepEqual(pure.outcome.value, word(10));
assert.deepEqual(pure.requests, []);
const effectful = await run(true, 7, 3, [19, 23]);
assert.equal(effectful.outcome.kind, 'completed');
assert.deepEqual(effectful.outcome.value, word(48));
assert.deepEqual(effectful.requests, [
  { identity: 'client/lookup', payload: '0700000000000000' },
  { identity: 'client/lookup', payload: '0700000000000000' },
]);
const pureOverflow = await run(false, 18446744073709551615n, 1, []);
assert.equal(pureOverflow.outcome.kind, 'failed');
assert.deepEqual(pureOverflow.requests, []);
const effectOverflow = await run(true, 7, 3, [18446744073709551615n]);
assert.equal(effectOverflow.outcome.kind, 'failed');
assert.equal(effectOverflow.requests.length, 1);
console.log(JSON.stringify({
  pure: 10, effectful: 48, requests: effectful.requests,
  pureOverflow: 'failed without requests',
  effectOverflow: 'failed after one request',
  nativeAgreement: !!nativePath,
}));
