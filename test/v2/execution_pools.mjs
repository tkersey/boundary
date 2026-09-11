import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { command } from '../../tools/v2/formal.mjs';

const [formalArgument, worldArgument, capacityArgument, ...extra] = process.argv.slice(2);
assert.ok(formalArgument && worldArgument && capacityArgument && !extra.length,
  'usage: execution_pools.mjs <formal-root> <world-root> <captured-capacity-directory>');
const formal = resolve(formalArgument), world = resolve(worldArgument), capacity = resolve(capacityArgument);
const { admitProcessKernel, encodeInput, encodeResult } = await import(
  pathToFileURL(join(world, 'src/process_v2/index.mjs')).href);
const image = await readFile(join(capacity, 'capacity.bpi2'));
const wasm = await readFile(join(capacity, 'normal.wasm'));
const kernel = await admitProcessKernel(wasm, {
  expectedSha256: createHash('sha256').update(wasm).digest('hex'),
});

// Distinct runs exercise multiple symbolic byte pools. Decimal 9 and 90 also
// distinguish whole numeral replacement from an incorrect prefix replacement.
// The 2 KiB message requires block-wise hash proofs within the kernel budget.
const argumentsBytes = new Uint8Array(2050);
argumentsBytes.set([128, 16]);
argumentsBytes.fill(9, 2, 1026);
argumentsBytes.fill(90, 1026);
const first = { image, initialArgs: argumentsBytes, mode: 'run' };
const requested = await kernel.run(first);
assert.equal(requested.kind, 'Requested');
const second = { image, state: requested.state,
  result: encodeResult(requested.request, new Uint8Array()), mode: 'run' };
const completed = await kernel.run(second);
assert.equal(completed.kind, 'Completed');
assert.deepEqual(completed.value, argumentsBytes);

const parent = join(formal, '.cache/execution-pools');
await mkdir(parent, { recursive: true });
const directory = await mkdtemp(join(parent, 'run-'));
const imagePath = join(directory, 'program.bpi2');
await writeFile(imagePath, image);
await writeFile(`${imagePath}.graph.borrow.json`,
  await readFile(join(capacity, 'capacity.bpi2.graph.borrow.json')));
const transitions = [];
for (const [index, [input, output]] of [
  [encodeInput(first), requested.bytes], [encodeInput(second), completed.bytes],
].entries()) {
  const inputPath = join(directory, `${index}.pki2`), outputPath = join(directory, `${index}.pko2`);
  await writeFile(inputPath, input);
  await writeFile(outputPath, output);
  transitions.push({ input: inputPath, output: outputPath, steps: 1 });
}
const manifest = join(directory, 'invocations.json');
await writeFile(manifest, JSON.stringify([{ name: 'pool-prefix-sibling', image: imagePath, transitions }]));
const proof = await command(process.execPath, [join(import.meta.dirname, 'execution_artifacts.mjs'),
  formal, manifest], resolve(import.meta.dirname, '../..'));
assert.equal(proof.code, 0, proof.text);
assert.equal(proof.signal, null);
assert.deepEqual(await readFile(join(capacity, 'capacity.bpi2')), image, 'execution_pools.image_changed');
assert.deepEqual(await readFile(join(capacity, 'normal.wasm')), wasm, 'execution_pools.kernel_changed');
console.log('execution pools: complete World execution, kernel/trust/replay and subject mutations passed');
