import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [bundle, baselinePath, candidatePath, sha256, nativePath] = process.argv.slice(2);
if (!bundle || !baselinePath || !candidatePath || !sha256 || !nativePath)
  throw new Error('usage: node authoring_one_world.mjs BUNDLE BASELINE CANDIDATE SHA NATIVE');
const { Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } =
  await import(pathToFileURL(join(bundle, 'runtime/src/embedding/index.mjs')).href);
const word = n => { const bytes = new Uint8Array(4);
  new DataView(bytes.buffer).setUint32(0, n, true); return bytes; };
async function run(path) {
  const image = readFileSync(path);
  const kernel = await Kernel.create({ bytes: readFileSync(join(bundle,
    'runtime/world-kernel.wasm')), expectedSha256: sha256 });
  const invoke = input => { const wasm = kernel.invoke(input);
    const native = spawnSync(nativePath, ['invoke'], { input, timeout: 30000 });
    assert.equal(native.status, 0, native.stderr.toString());
    assert.deepEqual(wasm, new Uint8Array(native.stdout));
    return decodeOutcome(wasm); };
  const requested = invoke(encodeInput({ image, initialArgs: word(7) }));
  assert.equal(requested.kind, 'requested');
  const request = await decodeRequest(requested.request);
  const terminal = invoke(encodeInput({ image, state: requested.state,
    control: 'reply', value: await encodeResult(requested.request, word(19)) }));
  assert.equal(terminal.kind, 'completed');
  return { identity: request.semanticIdentity,
    payload: Buffer.from(request.payload).toString('hex'),
    result: Buffer.from(terminal.value).toString('hex') };
}
const baseline = await run(baselinePath);
const candidate = await run(candidatePath);
assert.deepEqual(candidate, baseline);
assert.deepEqual(candidate, { identity: 'example.lookup.v2',
  payload: '07000000', result: '13000000' });
console.log(JSON.stringify({ baseline, candidate, nativeAgreement: true }));
