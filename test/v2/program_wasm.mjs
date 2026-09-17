import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";

const [probePath, emitter] = process.argv.slice(2);
const probe = await readFile(probePath);
const module = new WebAssembly.Module(probe);
assert.deepEqual(WebAssembly.Module.imports(module), []);
// Accepted installation budgets from optimized Boundary 2.0.2 at
// 42a09b92c2870ab3eab923fe68ca2645eb710000, on the unchanged source construction.
const predecessorLimits = new Map([[64, 2805], [128, 5574], [256, 12102]]);
const results = [];
for (const kind of ["install", "mixed", "irregular"]) {
  for (const count of [8, 64, 128, 256]) {
    const input = execFileSync(emitter, [String(count), kind], { maxBuffer: 1 << 20 });
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
    const limit = kind === "install" ? predecessorLimits.get(count) : undefined;
    if (limit !== undefined) assert.ok(length <= limit, `installation-${count} byte budget`);
    results.push({ kind, count, bpi3: length, predecessorLimit: limit, identity: expected.toString("hex") });
  }
}
console.log(JSON.stringify({ check: "BPI3 native/wasm32 byte and identity agreement", results }));
