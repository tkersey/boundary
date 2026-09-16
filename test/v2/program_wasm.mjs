import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";

const [probePath, emitter] = process.argv.slice(2);
const probe = await readFile(probePath);
const module = new WebAssembly.Module(probe);
assert.deepEqual(WebAssembly.Module.imports(module), []);
const results = [];
for (const kind of ["install", "mixed", "irregular"]) {
  for (const count of [8, 64, 128, 256]) {
    const input = execFileSync(emitter, [String(count), kind, "bpi3"], { maxBuffer: 1 << 20 });
    const { exports } = new WebAssembly.Instance(module, {});
    assert.ok(!(exports.memory.buffer instanceof SharedArrayBuffer));
    new Uint8Array(exports.memory.buffer, exports.compact_input_ptr(), input.length).set(input);
    const length = exports.program_encode(input.length);
    assert.equal(length, input.length, `${kind}-${count}`);
    const actual = new Uint8Array(exports.memory.buffer, exports.compact_output_ptr(), length);
    assert.deepEqual(actual, new Uint8Array(input));
    const identity = new Uint8Array(exports.memory.buffer, exports.program_identity_ptr(), 32);
    const expected = createHash("sha256").update("boundary.program/v3\0").update(input).digest();
    assert.deepEqual(identity, new Uint8Array(expected));
    assert.equal(exports.admitted_probe(input.length), 1, `${kind}-${count} immutable preparation`);
    assert.deepEqual(new Uint8Array(exports.memory.buffer, exports.program_identity_ptr(), 32), new Uint8Array(expected));
    const compact = execFileSync(emitter, [String(count), kind, "bpc1"], { maxBuffer: 1 << 20 });
    if (kind === "install" && count >= 64) assert.ok(length <= compact.length);
    results.push({ kind, count, bpi3: length, bpc1: compact.length, identity: expected.toString("hex") });
  }
}
console.log(JSON.stringify({ check: "BPI3 native/wasm32 byte and identity agreement", results }));
