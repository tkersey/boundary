import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [manifestPath, worldPath, nativePath, outputPath] = process.argv.slice(2);
assert.ok(manifestPath && worldPath && nativePath && outputPath && process.argv.length === 6,
  'usage: run_invocations.mjs <advance-manifest> <world-checkout> <native-records> <output-directory>');
const { body, decodeOutcome, Reader } = await import(pathToFileURL(join(resolve(worldPath), 'src/process_v2/codec.mjs')).href);
const groups = JSON.parse(await readFile(manifestPath, 'utf8'));
assert.ok(groups.length);
const output = resolve(outputPath), result = [];
await mkdir(output, { recursive: true });
function controlBytes(input) {
  const reader = new Reader(body('ABL_PKI2', input));
  reader.natural(); reader.field(); reader.natural(); reader.field();
  return reader.take(reader.bytes.length - reader.position);
}
const isInternalContinue = (control) => control.length === 2 && control[0] === 0 && control[1] === 0;
for (const group of groups) {
  const candidate = { name: group.name, image: group.image, states: [], transitions: [] };
  const retainedControls = [];
  async function invoke(input, expected, steps) {
    const control = controlBytes(input);
    if (!isInternalContinue(control)) retainedControls.push([...control]);
    const invoked = spawnSync(resolve(nativePath), [], { input, maxBuffer: 64 << 20, timeout: 120000 });
    assert.ifError(invoked.error);
    assert.equal(invoked.status, 0, `${group.name}: ${invoked.stderr}`);
    assert.equal(invoked.stderr.length, 0);
    assert.deepEqual(invoked.stdout, expected, `${group.name}: native invocation differs from advance sequence`);
    const stem = join(output, `${group.name}-${candidate.transitions.length}`);
    await writeFile(`${stem}.pki2`, input);
    await writeFile(`${stem}.pko2`, invoked.stdout);
    candidate.transitions.push({ input: `${stem}.pki2`, output: `${stem}.pko2`, steps });
    const outcome = decodeOutcome(invoked.stdout);
    if (outcome.state) {
      await writeFile(`${stem}.pst2`, outcome.state);
      candidate.states.push(`${stem}.pst2`);
    }
  }
  for (let first = 0; first < group.transitions.length;) {
    let last = first, interrupted = false;
    let expected = await readFile(group.transitions[last].output);
    while (decodeOutcome(expected).kind === 'Progressed') {
      assert.ok(last + 1 < group.transitions.length, 'inconclusive: missing continuation in advance segment');
      const next = await readFile(group.transitions[last + 1].input);
      if (!isInternalContinue(controlBytes(next))) { interrupted = true; break; }
      expected = await readFile(group.transitions[++last].output);
    }
    if (interrupted) {
      // A run cannot stop at an internal checkpoint to accept another control.
      // Preserve this prefix as exact advance invocations instead of skipping it.
      for (let index = first; index <= last; index++) {
        const original = group.transitions[index];
        await invoke(await readFile(original.input), await readFile(original.output), 1);
      }
    } else {
      // Mode is the first canonical natural. Every other byte stays unchanged.
      const input = await readFile(group.transitions[first].input);
      assert.equal(body('ABL_PKI2', input)[0], 0, 'expected advance input');
      input[20] = 1;
      await invoke(input, expected, last - first + 1);
    }
    first = last + 1;
  }
  const originalControls = [];
  for (const transition of group.transitions) {
    const control = controlBytes(await readFile(transition.input));
    if (!isInternalContinue(control)) originalControls.push([...control]);
  }
  assert.deepEqual(retainedControls, originalControls, `${group.name}: explicit control bytes changed or omitted`);
  result.push(candidate);
  console.log(`native run/advance: ${group.name}, ${candidate.transitions.length} complete invocations`);
}
await writeFile(join(output, 'inputs.json'), JSON.stringify(result));
console.log(`native run/advance: ${result.length} cases, ${result.reduce((sum, group) => sum + group.transitions.length, 0)} complete invocations`);
