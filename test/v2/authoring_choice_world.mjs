import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [bundle, allPath, firstPath, sha256, nativePath] = process.argv.slice(2);
if (!bundle || !allPath || !firstPath || !sha256 || !nativePath)
  throw new Error('usage: node authoring_choice_world.mjs BUNDLE ALL FIRST SHA NATIVE');
const { Kernel, encodeInput, decodeOutcome } = await import(
  pathToFileURL(join(bundle, 'runtime/src/embedding/index.mjs')).href);
for (const [name, path, expected] of [
  ['all', allPath, [4, 0, 0, 0, 1, 1, 0, 1, 1]],
  ['first', firstPath, [1, 0, 0]],
]) {
  const image = readFileSync(path);
  const input = encodeInput({ image, initialArgs: new Uint8Array() });
  const kernel = await Kernel.create({ bytes: readFileSync(join(bundle,
    'runtime/world-kernel.wasm')), expectedSha256: sha256 });
  const wasm = kernel.invoke(input);
  const native = spawnSync(nativePath, ['invoke'], { input, timeout: 30000 });
  assert.equal(native.status, 0, native.stderr.toString());
  assert.deepEqual(wasm, new Uint8Array(native.stdout));
  const outcome = decodeOutcome(wasm);
  assert.equal(outcome.kind, 'completed', name);
  assert.deepEqual(outcome.value, Uint8Array.from(expected), name);
}
console.log(JSON.stringify({ all: [false, false, true, true],
  first: [false], nativeAgreement: true }));
