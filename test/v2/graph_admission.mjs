import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { parseExactJson } from '../../tools/v2/exact_json.mjs';
import { cases } from './semantic_cases.mjs';
import { execute } from './source_oracle.mjs';

const [worldPath, nativePath, outputPath, filter] = process.argv.slice(2);
assert.ok(worldPath && nativePath && outputPath && process.argv.length <= 6,
  'usage: graph_admission.mjs <world-checkout> <native-records> <output-directory> [case-or-program]');
const root = resolve(new URL('../..', import.meta.url).pathname);
const output = resolve(outputPath), native = resolve(nativePath);
const { encodeInput, decodeOutcome, decodeRequest, encodeResult } =
  await import(pathToFileURL(join(resolve(worldPath), 'src/process_v2/index.mjs')).href);
await mkdir(output, { recursive: true });
const borrowCases = !filter || filter === 'borrow-returns' || filter.startsWith('borrow-return-')
  ? execFileSync(join(root, 'zig-out/bin/borrow-returns'), ['--sources'], { encoding: 'utf8', maxBuffer: 32 << 20 })
    .trim().split('\n').map((line) => parseExactJson(line)).filter((item) => !item.younger).map((item) => {
      const name = `borrow-return-${item.from}-${item.initial}-${item.delegated}`;
      return { name, program: name, source: item.source, initial: [], responses: [], cancellations: [] };
    })
  : [];
const allCases = [...cases, ...borrowCases];
const selected = filter === 'borrow-returns' ? borrowCases
  : filter ? allCases.filter((test) => test.name === filter || test.program === filter) : allCases;
assert.ok(selected.length);
const groups = [], compiled = new Map();
for (const test of selected) {
  if (!compiled.has(test.program)) {
    const sourcePath = test.source ? join(output, `${test.program}.source.json`)
      : join(root, 'zig-out', `source-${test.program}.json`);
    if (test.source) await writeFile(sourcePath, JSON.stringify(test.source));
    const image = join(output, `${test.program}.bpi2`), witness = join(output, `${test.program}.compiler.json`);
    execFileSync(join(root, 'zig-out/bin/boundary-certify-compile'),
      ['--source', sourcePath, '--image', image, '--witness', witness], { stdio: 'pipe' });
    const sourceBytes = await readFile(sourcePath), imageBytes = await readFile(image);
    const paired = parseExactJson(await readFile(witness));
    assert.deepEqual(Buffer.from(paired.source_bytes), sourceBytes);
    assert.deepEqual(Buffer.from(paired.image_bytes), imageBytes);
    compiled.set(test.program, { image, imageBytes, source: parseExactJson(sourceBytes) });
  }
  const program = compiled.get(test.program), expected = execute(program.source, test.initial, test.responses, test.cancellations);
  const group = { name: test.name, image: program.image, states: [], transitions: [] };
  const trace = [], controls = new Set();
  let responses = 0;
  async function invoke(input, repeatedRequest = false) {
    assert.ok(group.transitions.length < 100000, 'inconclusive: native segment test limit');
    const bytes = encodeInput({ image: program.imageBytes, mode: 'advance', ...input });
    const result = spawnSync(native, [], { input: bytes, maxBuffer: 64 << 20 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, `${test.name}: ${result.stderr}`);
    assert.equal(result.stderr.length, 0, `${test.name}: native diagnostics`);
    const stem = `${test.name}-${group.transitions.length}`;
    const inputFile = join(output, `${stem}.pki2`), outputFile = join(output, `${stem}.pko2`);
    await writeFile(inputFile, bytes);
    await writeFile(outputFile, result.stdout);
    group.transitions.push({ input: inputFile, output: outputFile });
    const step = decodeOutcome(new Uint8Array(result.stdout));
    assert.notEqual(step.kind, 'NeedsCapacity', 'inconclusive: native capacity');
    if (step.state) {
      const path = join(output, `${stem}.pst2`);
      await writeFile(path, step.state);
      group.states.push(path);
    }
    if (step.kind === 'Yielded') trace.push({ kind: 'Yielded' });
    if (step.kind === 'Requested' && !repeatedRequest) {
      const request = decodeRequest(step.request);
      trace.push({ kind: 'Requested', identity: request.semanticIdentity, payload: [...request.payload] });
    }
    return step;
  }
  let step = await invoke({ initialArgs: Uint8Array.from(test.initial) });
  while (['Progressed', 'Requested', 'Yielded'].includes(step.kind)) {
    // Consecutive controls belong to the same observed boundary even when
    // accepting the first cancellation returns an internal-progress snapshot.
    const pending = test.cancellations.findIndex((control, index) => control.at === trace.length - 1 && !controls.has(index));
    if (pending >= 0) {
      const control = test.cancellations[pending];
      controls.add(pending);
      step = await invoke({ state: step.state, cancel: control.reason }, control.preservesRequest && step.kind === 'Requested');
      continue;
    }
    const result = step.kind === 'Requested' ? encodeResult(step.request, Uint8Array.from(test.responses[responses++])) : undefined;
    step = await invoke({ state: step.state, result });
  }
  assert.equal(responses, test.responses.length, `${test.name}: response inventory`);
  assert.equal(controls.size, test.cancellations.length, `${test.name}: cancellation inventory`);
  const actual = { kind: step.kind, trace };
  if (step.value) actual.value = [...step.value];
  if (step.kind === 'Failed' || step.kind === 'Cancelled') {
    // The protocol encodes cleanup failures as a sequence of failure values;
    // the existing source/runtime suite owns that value decoding comparison.
    assert.ok(step.cleanupFailures);
    if (step.cancellation !== undefined) actual.cancellation = step.cancellation;
    if (step.reason !== undefined) actual.reason = step.reason;
  }
  assert.equal(actual.kind, expected.kind, test.name);
  assert.deepEqual(actual.trace, expected.trace, test.name);
  if (actual.value) assert.deepEqual(actual.value, expected.value, test.name);
  if (actual.reason !== undefined) assert.deepEqual(actual.reason, expected.reason, test.name);
  if (actual.cancellation !== undefined) assert.deepEqual(actual.cancellation, expected.cancellation, test.name);
  groups.push(group);
  console.log(`native graph input: ${test.name}, ${group.transitions.length} invocations, ${group.states.length} snapshots`);
}
const manifest = join(output, 'inputs.json');
await writeFile(manifest, JSON.stringify(groups));
execFileSync('lake', ['build', 'boundary-graph-conformance'], { cwd: join(root, 'semantics/v2'), stdio: 'pipe' });
execFileSync(join(root, 'semantics/v2/.lake/build/bin/boundary-graph-conformance'), [manifest],
  { cwd: join(root, 'semantics/v2'), stdio: 'inherit', timeout: 1800000 });
