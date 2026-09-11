import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [manifestPath, worldPath, kernelPath, nativePath, outputPath] = process.argv.slice(2);
assert.ok(process.argv.length === 7,
  'usage: rejected_invocations.mjs <run-manifest> <world-checkout> <kernel> <native-records> <output-directory>');
const { Reader, body, frame, concat, natural, field, encodeInput } =
  await import(pathToFileURL(join(resolve(worldPath), 'src/process_v2/codec.mjs')).href);
const { wasmRange, inspectProcessKernelWasm } =
  await import(pathToFileURL(join(resolve(worldPath), 'src/process_v2/wasm.mjs')).href);
const kernel = await readFile(kernelPath), native = await readFile(nativePath);
inspectProcessKernelWasm(kernel);
const module = await WebAssembly.compile(kernel);
const groups = JSON.parse(await readFile(manifestPath, 'utf8'));
const output = resolve(outputPath);
await mkdir(output, { recursive: true });
const temporary = await mkdtemp(join(output, '.adapter-'));
const adapter = join(temporary, 'records');
await writeFile(adapter, native, { mode: 0o700 });

function inputFields(bytes) {
  const reader = new Reader(body('ABL_PKI2', bytes));
  const mode = reader.natural() === 0n ? 'advance' : 'run';
  const image = reader.field(), selection = reader.natural(), instance = reader.field();
  const control = reader.natural();
  const result = control === 0n && reader.natural() === 1n ? reader.field() : undefined;
  return { mode, image, ...(selection === 0n ? { initialArgs: instance } : { state: instance }), result };
}

let initial, response, yielded;
for (const group of groups) {
  for (const item of group.transitions) {
    const bytes = await readFile(item.input), fields = inputFields(bytes);
    const subject = { bytes, fields, expected: await readFile(item.output), case: group.name };
    if (!initial && fields.initialArgs) initial = subject;
    if (!response && fields.result) response = subject;
    // Graph.Status assigns yielded = 1 after the complete 32-byte digest.
    if (!yielded && fields.state && body('ABL_PST2', fields.state)[32] === 1) yielded = subject;
    if (initial && response && yielded) break;
  }
  if (initial && response && yielded) break;
}
assert.ok(initial && response && yielded, 'rejection cohort requires initial, response, and yielded subjects');
const changedRequest = response.fields.result.slice(); changedRequest[20] ^= 1;
const changedSchema = response.fields.result.slice(); changedSchema[52] ^= 1;
const changedState = response.fields.state.slice(); changedState[20] ^= 1;
const invalidInitial = frame('ABL_PKI2', concat(natural(initial.fields.mode === 'run' ? 1 : 0),
  field(initial.fields.image), natural(0), field(initial.fields.initialArgs), natural(1), natural(0), field(new Uint8Array())));
const candidates = [
  ['wrong-request-digest', response, encodeInput({ ...response.fields, result: changedRequest }), 'InvalidResult'],
  ['wrong-response-schema', response, encodeInput({ ...response.fields, result: changedSchema }), 'InvalidResult'],
  ['wrong-state-program-identity', response, encodeInput({ ...response.fields, state: changedState }), 'InvalidState'],
  ['invalid-initial-control', initial, invalidInitial, 'InvalidControl'],
  ['response-to-yielded-state', yielded, encodeInput({ ...yielded.fields, result: response.fields.result }), 'InvalidControl'],
];

function invokeNative(input) {
  const result = spawnSync(adapter, [], { input, timeout: 120000, maxBuffer: 64 << 20 });
  assert.ifError(result.error); assert.equal(result.signal, null);
  return { status: result.status, output: result.stdout, error: result.stderr, after: input.slice() };
}

function invokeWasm(exports, input) {
  assert.equal(exports.world_process_v2_prepare_input(BigInt(input.length)), 0);
  const pointer = exports.world_process_v2_input_ptr();
  wasmRange(exports.memory, pointer, BigInt(input.length), 'input').set(input);
  const status = exports.world_process_v2_execute(BigInt(input.length));
  return { status,
    output: wasmRange(exports.memory, exports.world_process_v2_output_ptr(),
      BigInt.asUintN(64, exports.world_process_v2_output_len()), 'output').slice(),
    error: wasmRange(exports.memory, exports.world_process_v2_error_ptr(),
      BigInt.asUintN(64, exports.world_process_v2_error_len()), 'error').slice(),
    after: wasmRange(exports.memory, pointer, BigInt(input.length), 'input').slice() };
}

const records = [];
try {
  for (const [name, baseline, input, expectedError] of candidates) {
    const { exports } = await WebAssembly.instantiate(module, {});
    // Begin with a real output so rejection must clear it, then retry in that
    // same instance with the exact original input.
    assert.deepEqual(Buffer.from(invokeWasm(exports, baseline.bytes).output), baseline.expected);
    for (const producer of ['native', 'wasm']) {
      const actual = producer === 'native' ? invokeNative(input) : invokeWasm(exports, input);
      assert.equal(producer === 'native' ? actual.status !== 0 : actual.status === 2, true);
      assert.equal(actual.output.length, 0, 'rejection published an output or retained stale output');
      assert.deepEqual(Buffer.from(actual.after), Buffer.from(input), 'rejection changed caller-visible input');
      const diagnostic = new TextDecoder().decode(actual.error);
      assert.equal(producer === 'native' ? diagnostic.startsWith(`error: ${expectedError}\n`) : diagnostic === expectedError,
        true, `${name}: ${diagnostic}`);
      const stem = join(output, `${name}-${producer}`);
      await writeFile(`${stem}.pki2`, input); await writeFile(`${stem}.output`, actual.output);
      await writeFile(`${stem}.error`, actual.error); await writeFile(`${stem}.input-after`, actual.after);
      const retry = producer === 'native' ? invokeNative(baseline.bytes) : invokeWasm(exports, baseline.bytes);
      assert.equal(retry.status, 0); assert.equal(retry.error.length, 0);
      assert.deepEqual(Buffer.from(retry.output), baseline.expected);
      assert.deepEqual(Buffer.from(retry.after), baseline.bytes);
      await writeFile(`${stem}.retry.pki2`, baseline.bytes); await writeFile(`${stem}.retry.pko2`, retry.output);
      records.push({ name, case: baseline.case, producer, expectedError, status: actual.status,
        input: `${stem}.pki2`, output: `${stem}.output`, error: `${stem}.error`, inputAfter: `${stem}.input-after`,
        retryInput: `${stem}.retry.pki2`, retryOutput: `${stem}.retry.pko2` });
    }
    console.log(`rejected invocation: ${name}, exact native/WASM errors, empty output, unchanged input and retry`);
  }
  assert.deepEqual(await readFile(kernelPath), kernel); assert.deepEqual(await readFile(nativePath), native);
  const identity = (bytes) => ({ length: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') });
  await writeFile(join(output, 'records.json'), JSON.stringify({ kernel: identity(kernel), native: identity(native), records }));
} finally { await rm(temporary, { recursive: true, force: true }); }
