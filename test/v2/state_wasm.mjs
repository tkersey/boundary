import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const module = new WebAssembly.Module(await readFile(process.argv[2]));
assert.deepEqual(WebAssembly.Module.imports(module), []);
// Independent scalar terminal and mid-instruction activation grammar witnesses.
const cases = [
  [4, 0, 0, 0, 1, 0, 0, 1, 23, 0, 0, 0, ...Array(8).fill(0), ...Array(7).fill(0)],
  [0, 1, 0, 0, 0, 0, 0, // active; current node 0; other roots absent
    1, 0, 0, 0, 0, 0, // one control: tag, block, parent, evidence, region
    1, 3, 0, 1, 8, 0, 0, 42, ...Array(7).fill(0), 0, 0],
];
for (const fields of cases) {
  const body = new Uint8Array([...Array(32).fill(0), ...fields]);
  const bytes = new Uint8Array(20 + body.length);
  bytes.set(new TextEncoder().encode("ABL_PST3"));
  const header = new DataView(bytes.buffer);
  header.setUint16(8, 3, true);
  header.setBigUint64(12, BigInt(body.length), true);
  bytes.set(body, 20);
  const { exports } = new WebAssembly.Instance(module, {});
  assert.ok(!(exports.memory.buffer instanceof SharedArrayBuffer));
  const input = new Uint8Array(exports.memory.buffer, exports.compact_input_ptr(), bytes.length);
  input.set(bytes);
  const length = exports.state_encode(bytes.length);
  assert.equal(length, bytes.length);
  assert.deepEqual(new Uint8Array(exports.memory.buffer, exports.compact_output_ptr(), length), bytes);
  input[10] = 1;
  assert.equal(exports.state_encode(bytes.length), 0);
}
console.log("PST3 wasm32 golden re-encoding and malformed framing: 2 cases passed");
