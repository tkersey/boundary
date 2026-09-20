// Finite partiality observation. Exhaustion is not a semantic answer.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
const [world, kernelPath, imagePath] = process.argv.slice(2);
const { Kernel, decodeOutcome } = await import(pathToFileURL(resolve(world)));
const bytes = new Uint8Array(await readFile(kernelPath));
const image = new Uint8Array(await readFile(imagePath));
const expectedSha256 = createHash('sha256').update(bytes).digest('hex');
let instanceId = 1n;
const fresh = () => Kernel.create({ bytes, expectedSha256, instanceId: instanceId++ });
let kernel = await fresh(), prepared = kernel.prepare(image), session = kernel.start(prepared);
kernel.releasePrepared(prepared);
for (let round = 0; round < 8; round++) {
  const outcome = decodeOutcome(kernel.drive(session, { quantum: 8, checkpoint: true }));
  assert.equal(outcome.kind, 'progressed');
  const state = kernel.checkpoint(session, { transfer: true });
  assert.deepEqual(state, outcome.state);
  assert.equal(kernel.usage().workingLive, 0n);
  kernel = await fresh(); prepared = kernel.prepare(image); session = kernel.restore(prepared, state);
  kernel.releasePrepared(prepared);
}
const cancelled = decodeOutcome(kernel.drive(session, { control: 'cancel_text', value: 'end observation' }));
assert.equal(cancelled.kind, 'cancelled');
kernel.close(session);
assert.equal(kernel.usage().workingLive, 0n);
console.log(JSON.stringify({ observation: '8 exhausted quanta; no semantic result',
  quantum: 8, transferred: 8, cancellation: 'separate operational stop', imageBytes: image.length }));
