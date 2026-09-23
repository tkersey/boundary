// Independent higher-order oracle versus bounded generated public authoring.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {reference} from './hyperfunction_reference.mjs';

const [emitter, entry, kernelPath] = process.argv.slice(2);
assert(emitter && entry && kernelPath && process.argv.length === 5,
  'usage: node test/hyper_generated.mjs EMITTER WORLD_ENTRY KERNEL');
const {Kernel, decodeOutcome} = await import(pathToFileURL(resolve(entry)));
const bytes = new Uint8Array(await readFile(kernelPath));
const expectedSha256 = createHash('sha256').update(bytes).digest('hex');
const constructors = new Set();
function meaning(seed, variant) {
  const h = reference(100000);
  function next() {
    seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5;
    return seed >>> 0;
  }
  function generate(depth) {
    const kind = next() % (depth === 0 ? 3 : 6);
    constructors.add(kind);
    if (kind < 3) {
      const value = BigInt(next() % 23);
      if (kind === 0) return h.base(h.delay(() => value));
      if (kind === 1) {
        const constant = BigInt(next() % 23);
        return h.lift(() => h.delay(() => constant));
      }
      return h.make(() => h.delay(() => value));
    }
    if (kind === 3) {
      const increment = BigInt(next() % 7), tail = generate(depth - 1);
      return h.push(x => h.delay(() => h.force(x) + increment), h.delay(() => tail));
    }
    if (kind === 4) return h.compose(generate(depth - 1), generate(depth - 1));
    return h.compose(h.identity(), generate(depth - 1));
  }
  let term = generate(3);
  if (variant === 2) term = h.compose(h.identity(), term);
  if (variant === 3) term = h.compose(term, h.identity());
  if (variant >= 4) {
    const left = h.lift(x => h.delay(() => h.force(x) + 2n));
    const right = h.lift(x => h.delay(() => h.force(x) + 3n));
    term = variant === 4 ? h.compose(left, h.compose(right, term))
      : h.compose(h.compose(left, right), term);
  }
  // Exhaustion throws; two exhausted computations are never called equivalent.
  return h.force(variant === 1 ? h.project(term, h.delay(() => 7n)) : h.run(term));
}
let instanceId = 1n, transfers = 0, maximumImage = 0;
async function execute(image) {
  let state, result;
  for (let quantum = 0; quantum < 1000; quantum++) {
    const kernel = await Kernel.create({bytes, expectedSha256, instanceId: instanceId++});
    kernel.setLimits({input: 2 << 20, working: 8 << 20, output: 2 << 20});
    const program = kernel.prepare(image);
    const session = state ? kernel.restore(program, state) : kernel.start(program, new Uint8Array());
    kernel.releasePrepared(program);
    const out = decodeOutcome(kernel.drive(session, {quantum: 97, checkpoint: true}));
    if (out.kind === 'completed') {
      result = new DataView(out.value.buffer, out.value.byteOffset, out.value.byteLength)
        .getBigUint64(0, true);
      kernel.close(session);
    } else {
      assert.equal(out.kind, 'progressed');
      state = kernel.checkpoint(session, {transfer: true});
      assert.deepEqual(state, out.state);
      transfers++;
    }
    assert.equal(kernel.usage().workingLive, 0n);
    if (result !== undefined) return result;
  }
  throw Error('finite observation allowance exhausted; no semantic equality established');
}
const rows = [];
for (const seed of [1, 2, 3, 7, 11, 19, 31, 47, 67, 97, 131, 193, 257, 521, 1021, 65537]) {
  const values = [];
  for (let variant = 0; variant < 6; variant++) {
    const expected = meaning(seed, variant);
    const image = new Uint8Array(execFileSync(resolve(emitter), [String(seed), String(variant)],
      {maxBuffer: 2 << 20, timeout: 30000}));
    maximumImage = Math.max(maximumImage, image.length);
    const actual = await execute(image);
    assert.equal(actual, expected, `seed=${seed}, variant=${variant}`);
    values.push(actual);
  }
  assert.equal(values[0], values[2], 'left identity');
  assert.equal(values[0], values[3], 'right identity');
  assert.equal(values[4], values[5], 'associativity with lifted additions');
  rows.push({seed, values: values.map(String)});
}
assert.deepEqual([...constructors].sort(), [0, 1, 2, 3, 4, 5]);
console.log(JSON.stringify({cases: rows.length * 6, depth: 3, constructors: [...constructors].sort(),
  transfers, maximumImage, kernelSha256: expectedSha256, rows}));
