import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [bundle, imagePath, sha256, nativePath] = process.argv.slice(2);
if (!bundle || !imagePath || !sha256 || !nativePath)
  throw new Error('usage: node authoring_config_world.mjs BUNDLE IMAGE SHA NATIVE');
const { Kernel, encodeInput, decodeOutcome } = await import(
  pathToFileURL(join(bundle, 'runtime/src/embedding/index.mjs')).href);
const word = n => { const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setBigUint64(0, BigInt(n), true); return bytes; };
const image = readFileSync(imagePath);
const kernel = await Kernel.create({ bytes: readFileSync(join(bundle,
  'runtime/world-kernel.wasm')), expectedSha256: sha256 });
const input = encodeInput({ image, initialArgs: word(10) });
const wasm = kernel.invoke(input);
const native = spawnSync(nativePath, ['invoke'], { input, timeout: 30000 });
assert.equal(native.status, 0, native.stderr.toString());
assert.deepEqual(wasm, new Uint8Array(native.stdout));
const result = decodeOutcome(wasm);
assert.equal(result.kind, 'completed');
assert.deepEqual(result.value, new Uint8Array([...word(11), ...word(12), ...word(11)]));
console.log(JSON.stringify({ configurationResults: [11, 12, 11],
  nativeAgreement: true }));
