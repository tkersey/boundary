import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [bundle, imagePath, sha256, nativePath] = process.argv.slice(2);
if (!bundle || !imagePath || !sha256 || !nativePath)
  throw new Error('usage: node authoring_bypass_world.mjs BUNDLE IMAGE SHA NATIVE');
const { Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } =
  await import(pathToFileURL(join(bundle, 'runtime/src/embedding/index.mjs')).href);
const image = readFileSync(imagePath);
const word = n => { const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setBigUint64(0, BigInt(n), true); return bytes; };

for (const bypass of [false, true]) {
  const kernel = await Kernel.create({ bytes: readFileSync(join(bundle,
    'runtime/world-kernel.wasm')), expectedSha256: sha256 });
  const invoke = input => {
    const wasm = kernel.invoke(input);
    const native = spawnSync(nativePath, ['invoke'], { input, timeout: 30000 });
    assert.equal(native.status, 0, native.stderr.toString());
    assert.deepEqual(wasm, new Uint8Array(native.stdout));
    return decodeOutcome(wasm);
  };
  let outcome = invoke(encodeInput({ image,
    initialArgs: Uint8Array.of(bypass ? 1 : 0) }));
  const trace = [];
  for (let index = 0; index < 4 && outcome.kind === 'requested'; index++) {
    const request = await decodeRequest(outcome.request);
    assert.equal(request.semanticIdentity, 'authoring/probe');
    trace.push(Buffer.from(request.payload).toString('hex'));
    outcome = invoke(encodeInput({ image, state: outcome.state,
      control: 'reply', value: await encodeResult(outcome.request, new Uint8Array()) }));
  }
  assert.equal(outcome.kind, 'completed');
  assert.deepEqual(outcome.value, word(bypass ? 99 : 113));
  assert.deepEqual(trace, bypass ? ['0100000000000000'] :
    ['0100000000000000', '0200000000000000']);
}
console.log(JSON.stringify({ resumed: { value: 113, probes: [1, 2] },
  bypassed: { value: 99, probes: [1] }, nativeAgreement: true }));
