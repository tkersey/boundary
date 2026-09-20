// Execute an emitted pure witness using the separately supplied ordinary World.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [world, kernelPath, imagePath] = process.argv.slice(2);
if (!world || !kernelPath || !imagePath || process.argv.length !== 5)
  throw new Error('usage: node test/hyperfunction_world.mjs WORLD_ENTRY KERNEL IMAGE');
const { Kernel, decodeOutcome } = await import(pathToFileURL(resolve(world)));
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
for (let round = 0; ; round++) {
  assert.ok(round < 100, 'constant witness did not finish within its finite observation');
  const outcome = decodeOutcome(kernel.drive(session, { quantum: 1, checkpoint: true }));
  if (outcome.kind === 'completed') {
    assert.equal(new DataView(outcome.value.buffer, outcome.value.byteOffset,
      outcome.value.byteLength).getBigUint64(0, true), 42n);
    kernel.close(session);
    assert.equal(kernel.usage().workingLive, 0n);
    break;
  }
  assert.equal(outcome.kind, 'progressed');
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
console.log(JSON.stringify({ value: 42, imageBytes: image.length, transfers,
  kernelSha256: expectedSha256 }));
