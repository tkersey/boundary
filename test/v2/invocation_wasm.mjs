import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";

const module = new WebAssembly.Module(await readFile(process.argv[2]));
assert.deepEqual(WebAssembly.Module.imports(module), []);
const field = bytes => [bytes.length, ...bytes]; // All fixture lengths are below 128.
const scalar = [42, 0, 0, 0, 0, 0, 0, 0];
const binding = new Uint8Array([
  ...Array(32).fill(1), ...Array(32).fill(2), 3,
  ...field(new TextEncoder().encode("operation")),
  ...field([0, 1, 9]), ...field([0, 1, 1]), ...field(scalar),
]);
const identity = createHash("sha256").update("boundary.effect-request/v3\0").update(binding).digest();
const cases = [
  ["PKI3", [0, 0, 0, 0, 1, 0]],
  ["PKO3", [3, ...field(scalar)]],
  ["ERQ3", [...binding, ...identity]],
  ["ERS3", [...identity, ...field([1])]],
];
for (const [kind, [family, body]] of cases.entries()) {
  const bytes = new Uint8Array(20 + body.length);
  bytes.set(new TextEncoder().encode(`ABL_${family}`));
  const header = new DataView(bytes.buffer);
  header.setUint16(8, 3, true);
  header.setBigUint64(12, BigInt(body.length), true);
  bytes.set(body, 20);
  const { exports } = new WebAssembly.Instance(module, {});
  const input = new Uint8Array(exports.memory.buffer, exports.compact_input_ptr(), bytes.length);
  input.set(bytes);
  const length = exports.invocation_encode(kind, bytes.length);
  assert.equal(length, bytes.length, family);
  assert.deepEqual(new Uint8Array(exports.memory.buffer, exports.compact_output_ptr(), length), bytes);
  input[7] = 50; // Old family digit.
  assert.equal(exports.invocation_encode(kind, bytes.length), 0);
}
console.log("PKI3/PKO3/ERQ3/ERS3 independent wasm32 bytes and request identity: passed");
