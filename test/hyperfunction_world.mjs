// Execute an emitted pure witness using the separately supplied ordinary World.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [world, kernelPath, imagePath, expected = 'completed'] = process.argv.slice(2);
if (!world || !kernelPath || !imagePath || process.argv.length > 6 || !['completed','failed','effect'].includes(expected))
  throw new Error('usage: node test/hyperfunction_world.mjs WORLD_ENTRY KERNEL IMAGE [completed|failed|effect]');
const { Kernel, decodeOutcome, decodeRequest, encodeResult } = await import(pathToFileURL(resolve(world)));
const bytes = new Uint8Array(await readFile(kernelPath));
const image = new Uint8Array(await readFile(imagePath));
const expectedSha256 = createHash('sha256').update(bytes).digest('hex');
let instanceId = 1n;
async function fresh() {
  const kernel = await Kernel.create({ bytes, expectedSha256, instanceId: instanceId++ });
  kernel.setLimits({ input: 2 << 20, working: 8 << 20, output: 2 << 20 });
  return kernel;
}
let kernel = await fresh();
let prepared = kernel.prepare(image);
let session = kernel.start(prepared, new Uint8Array());
kernel.releasePrepared(prepared);
let transfers = 0;
let requests = 0, control = 'none', value = new Uint8Array();
for (let round = 0; ; round++) {
  assert.ok(round < 100, 'constant witness did not finish within its finite observation');
  const outcome = decodeOutcome(kernel.drive(session, { control, value, quantum: 1, checkpoint: true }));
  if (['completed', 'failed'].includes(outcome.kind)) {
    assert.equal(outcome.kind, expected === 'effect' ? 'completed' : expected);
    assert.equal(requests, expected === 'effect' ? 1 : 0);
    if (expected !== 'failed') assert.equal(new DataView(outcome.value.buffer, outcome.value.byteOffset,
      outcome.value.byteLength).getBigUint64(0, true), 42n);
    else { assert.deepEqual(outcome.value, new Uint8Array()); assert.deepEqual(outcome.cleanupFailures, []); }
    kernel.close(session);
    assert.equal(kernel.usage().workingLive, 0n);
    break;
  }
  if (outcome.kind === 'requested') {
    assert.equal(expected, 'effect');
    const request = await decodeRequest(outcome.request);
    assert.equal(request.semanticIdentity, 'hyper/reference');
    assert.deepEqual(request.payload, Uint8Array.of(19,0,0,0,0,0,0,0));
    requests++;
    value = await encodeResult(outcome.request, request.payload);
    control = 'reply';
  } else {
    assert.equal(outcome.kind, 'progressed');
    control = 'none'; value = new Uint8Array();
  }
  const state = kernel.checkpoint(session, { transfer: true });
  assert.deepEqual(state, outcome.state);
  assert.throws(() => kernel.drive(session), { code: 'WORLD_HANDLE_INVALID' });
  assert.equal(kernel.usage().workingLive, 0n);
  kernel = await fresh();
  prepared = kernel.prepare(image);
  session = kernel.restore(prepared, state);
  kernel.releasePrepared(prepared);
  transfers++;
}
console.log(JSON.stringify({ expected, value: expected !== 'failed' ? 42 : 'authored unit failure', requests, imageBytes: image.length, transfers,
  kernelSha256: expectedSha256 }));
