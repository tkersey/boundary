// External execution adapter; all branching remains in the compiled Program.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const [runtime, imagePath] = process.argv.slice(2);
assert.ok(runtime && imagePath, 'usage: node test/structured_authoring.mjs RUNTIME_DIR IMAGE');
const {Kernel, decodeOutcome, decodeRequest, encodeResult} =
  await import(pathToFileURL(resolve(runtime, 'src/embedding/index.mjs')));
const bytes = new Uint8Array(await readFile(resolve(runtime, 'world-kernel.wasm')));
const image = new Uint8Array(await readFile(imagePath));
const expectedSha256 = 'df7fe1ae0ed0de7b2976c98b1534d1d55f4c341b7148837ce32f42ed8d011084';
const integer = n => { const b = new Uint8Array(8); new DataView(b.buffer).setBigUint64(0,n,true); return b; };
for (const choice of [false, true]) {
  let kernel = await Kernel.create({bytes, expectedSha256});
  let prepared = kernel.prepare(image);
  let session = kernel.start(prepared, Uint8Array.of(Number(choice)));
  kernel.releasePrepared(prepared);
  let outcome = decodeOutcome(kernel.drive(session, {checkpoint: true}));
  let requests = 0;
  for (let round=0; round<100; round++) {
    if (outcome.kind === 'completed') {
      assert.deepEqual(outcome.value, integer(choice ? 71n : 42n));
      assert.equal(requests, Number(choice));
      kernel.close(session);
      break;
    }
    if (outcome.kind === 'requested') {
      requests++;
      const request = await decodeRequest(outcome.request);
      assert.equal(request.semanticIdentity, 'authoring/lookup');
      assert.deepEqual(request.payload, integer(19n));
      const state = kernel.checkpoint(session, {transfer: true});
      kernel = await Kernel.create({bytes, expectedSha256});
      prepared = kernel.prepare(image);
      session = kernel.restore(prepared, state);
      kernel.releasePrepared(prepared);
      outcome = decodeOutcome(kernel.drive(session));
      assert.equal(outcome.kind, 'requested');
      outcome = decodeOutcome(kernel.drive(session, {control:'reply',
        value:await encodeResult(outcome.request, integer(71n)), checkpoint:true}));
    } else {
      assert.equal(outcome.kind, 'progressed');
      outcome = decodeOutcome(kernel.drive(session, {checkpoint:true}));
    }
  }
  assert.equal(outcome.kind, 'completed');
}
console.log('structured authoring: both branches, residual request and fresh restoration passed');
