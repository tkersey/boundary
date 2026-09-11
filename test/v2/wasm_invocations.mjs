import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [manifestPath, worldPath, kernelPath, outputPath, nativePath] = process.argv.slice(2);
assert.ok(manifestPath && worldPath && kernelPath && outputPath && process.argv.length <= 7,
  'usage: wasm_invocations.mjs <native-manifest> <world-checkout> <kernel> <output-directory> [alternating-native-records]');
const { wasmRange, inspectProcessKernelWasm } =
  await import(pathToFileURL(join(resolve(worldPath), 'src/process_v2/wasm.mjs')).href);
const { decodeOutcome, Reader, body, frame, field, natural, concat } =
  await import(pathToFileURL(join(resolve(worldPath), 'src/process_v2/codec.mjs')).href);
const kernel = await readFile(kernelPath);
const nativeBytes = nativePath ? await readFile(nativePath) : null;
const label = nativePath ? 'alternating runtime' : 'WASM invocation';
inspectProcessKernelWasm(kernel);
const module = await WebAssembly.compile(kernel);
const groups = JSON.parse(await readFile(manifestPath, 'utf8'));
assert.ok(groups.length);
const output = resolve(outputPath), result = [];
await mkdir(output, { recursive: true });
const adapterDirectory = nativeBytes ? await mkdtemp(join(output, '.native-adapter-')) : null;
const adapterPath = adapterDirectory ? join(adapterDirectory, 'records') : null;
if (adapterPath) await writeFile(adapterPath, nativeBytes, { mode: 0o700 });
let total = 0;
try {
for (const group of groups) {
  const candidate = { name: group.name, image: group.image, states: [], transitions: [] };
  let previous = null;
  for (const [index, invocation] of group.transitions.entries()) {
    let input = await readFile(invocation.input);
    const expected = await readFile(invocation.output);
    if (previous !== null) {
      const reader = new Reader(body('ABL_PKI2', input));
      const mode = reader.natural(), image = reader.field(), selection = reader.natural();
      assert.equal(selection, 1n, 'successor must restore the preceding output');
      assert.deepEqual(Buffer.from(reader.field()), Buffer.from(previous));
      const restored = frame('ABL_PKI2', concat(natural(mode), field(image), natural(selection),
        field(previous), reader.bytes.subarray(reader.position)));
      assert.deepEqual(Buffer.from(restored), input);
      input = restored;
    }
    let actual, afterInput, status, error;
    const producer = nativePath && index % 2 ? 'native' : 'wasm';
    if (producer === 'native') {
      const result = spawnSync(adapterPath, [], { input, maxBuffer: 64 << 20, timeout: 120000 });
      assert.ifError(result.error);
      status = result.status;
      error = result.stderr;
      actual = result.stdout;
      afterInput = input.slice();
    } else {
      const { exports } = await WebAssembly.instantiate(module, {});
      assert.equal(exports.world_process_v2_abi_version(), 2);
      assert.equal(exports.world_process_v2_prepare_input(BigInt(input.length)), 0, 'inconclusive: input reservation');
      const pointer = exports.world_process_v2_input_ptr();
      wasmRange(exports.memory, pointer, BigInt(input.length), 'input').set(input);
      status = exports.world_process_v2_execute(BigInt(input.length));
      error = wasmRange(exports.memory, exports.world_process_v2_error_ptr(),
        BigInt.asUintN(64, exports.world_process_v2_error_len()), 'error').slice();
      actual = wasmRange(exports.memory, exports.world_process_v2_output_ptr(),
        BigInt.asUintN(64, exports.world_process_v2_output_len()), 'output').slice();
      afterInput = wasmRange(exports.memory, pointer, BigInt(input.length), 'input').slice();
    }
    assert.equal(status, 0, `${group.name}: ${new TextDecoder().decode(error)}`);
    assert.equal(error.length, 0);
    assert.deepEqual(Buffer.from(actual), expected, `${group.name}: complete native/WASM output differs`);
    assert.deepEqual(Buffer.from(afterInput), Buffer.from(input), 'kernel changed caller-visible input bytes');
    const stem = join(output, `${group.name}-${index}`);
    await writeFile(`${stem}.pki2`, input);
    await writeFile(`${stem}.pko2`, actual);
    await writeFile(`${stem}.input-after`, afterInput);
    candidate.transitions.push({ ...invocation, input: `${stem}.pki2`, output: `${stem}.pko2`,
      inputAfter: `${stem}.input-after`, status, error: [...error], producer });
    const outcome = decodeOutcome(actual);
    previous = outcome.state ?? null;
    if (outcome.state) {
      await writeFile(`${stem}.pst2`, outcome.state);
      candidate.states.push(`${stem}.pst2`);
    }
    total += 1;
    if (total % 1000 === 0) console.log(`${label}: ${total} complete records matched`);
  }
  result.push(candidate);
  console.log(`${label}: ${group.name}, ${candidate.transitions.length} complete records matched`);
}
await writeFile(join(output, 'inputs.json'), JSON.stringify(result));
await writeFile(join(output, 'kernel.json'), JSON.stringify({
  path: resolve(kernelPath), length: kernel.length, sha256: createHash('sha256').update(kernel).digest('hex'),
  cases: result.length, invocations: total,
  native: nativeBytes ? { path: resolve(nativePath), length: nativeBytes.length,
    sha256: createHash('sha256').update(nativeBytes).digest('hex') } : null,
}));
assert.deepEqual(await readFile(kernelPath), kernel, 'kernel changed during capture');
if (nativeBytes) assert.deepEqual(await readFile(nativePath), nativeBytes, 'native adapter changed during capture');
console.log(`${label}: ${result.length} cases, ${total} complete outputs and unchanged inputs`);
} finally {
  if (adapterDirectory) await rm(adapterDirectory, { recursive: true, force: true });
}
