import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [manifestPath, worldPath, nativePath, outputPath] = process.argv.slice(2);
assert.ok(manifestPath && worldPath && nativePath && outputPath && process.argv.length === 6,
  'usage: run_invocations.mjs <advance-manifest> <world-checkout> <native-records> <output-directory>');
const { body, decodeOutcome } = await import(pathToFileURL(join(resolve(worldPath), 'src/process_v2/codec.mjs')).href);
const groups = JSON.parse(await readFile(manifestPath, 'utf8'));
assert.ok(groups.length);
const output = resolve(outputPath), result = [];
await mkdir(output, { recursive: true });
for (const group of groups) {
  const candidate = { name: group.name, image: group.image, states: [], transitions: [] };
  for (let first = 0; first < group.transitions.length;) {
    let last = first;
    let expected = await readFile(group.transitions[last].output);
    while (decodeOutcome(expected).kind === 'Progressed') {
      last += 1;
      assert.ok(last < group.transitions.length, 'inconclusive: missing continuation in advance segment');
      expected = await readFile(group.transitions[last].output);
    }
    // PKI2 mode is the first canonical natural in the framed body. Preserve
    // every other input byte, including exact image, state and control fields.
    const input = await readFile(group.transitions[first].input);
    assert.equal(body('ABL_PKI2', input)[0], 0, 'expected advance input');
    input[20] = 1;
    const invoked = spawnSync(resolve(nativePath), [], { input, maxBuffer: 64 << 20, timeout: 120000 });
    assert.ifError(invoked.error);
    assert.equal(invoked.status, 0, `${group.name}: ${invoked.stderr}`);
    assert.equal(invoked.stderr.length, 0);
    assert.deepEqual(invoked.stdout, expected, `${group.name}: native run differs from complete advance sequence`);
    const stem = join(output, `${group.name}-${candidate.transitions.length}`);
    await writeFile(`${stem}.pki2`, input);
    await writeFile(`${stem}.pko2`, invoked.stdout);
    candidate.transitions.push({ input: `${stem}.pki2`, output: `${stem}.pko2`, steps: last - first + 1 });
    const outcome = decodeOutcome(invoked.stdout);
    if (outcome.state) {
      await writeFile(`${stem}.pst2`, outcome.state);
      candidate.states.push(`${stem}.pst2`);
    }
    first = last + 1;
  }
  result.push(candidate);
  console.log(`native run: ${group.name}, ${candidate.transitions.length} complete invocations`);
}
await writeFile(join(output, 'inputs.json'), JSON.stringify(result));
console.log(`native run: ${result.length} cases, ${result.reduce((sum, group) => sum + group.transitions.length, 0)} complete invocations`);
