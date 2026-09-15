// Same logical inputs and deterministic writer policy on native and wasm32 targets.
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { createHash } from "node:crypto";

const [probePath, nativePath, fixtures] = process.argv.slice(2);
assert.ok(fixtures, "codec WASM probe, native compact converter, fixture directory");
const probe = await readFile(probePath);
const module = new WebAssembly.Module(probe);
assert.deepEqual(WebAssembly.Module.imports(module), []);
const files = (await readdir(fixtures)).filter(file => file.endsWith(".bpi2")).sort();
for (const required of ["install-64.bpi2", "install-128.bpi2", "mixed-64.bpi2", "source-queens-dfs.bpi2"])
  assert.ok(files.includes(required), required);
for (const file of files) {
  const bytes = await readFile(join(fixtures, file));
  assert.ok(bytes.length <= 1 << 20);
  const expected = execFileSync(nativePath, { input: bytes, maxBuffer: 1 << 20 });
  const { exports } = new WebAssembly.Instance(module, {});
  new Uint8Array(exports.memory.buffer, exports.compact_input_ptr(), bytes.length).set(bytes);
  const length = exports.compact_encode(bytes.length);
  assert.ok(length > 0, file);
  const actual = new Uint8Array(exports.memory.buffer, exports.compact_output_ptr(), length);
  assert.deepEqual(actual, new Uint8Array(expected), file);
}
console.log(JSON.stringify({ check: "native/wasm32 compact writer byte agreement", images: files.length,
  codecProbeSha256: createHash("sha256").update(probe).digest("hex") }));
