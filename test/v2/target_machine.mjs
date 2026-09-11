import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { parseExactJson } from '../../tools/v2/exact_json.mjs';
import { exactValueWitness, decodeValueWitness } from '../../tools/v2/source_value_witness.mjs';
import { cases, programNames } from './semantic_cases.mjs';
import { execute } from './source_oracle.mjs';

const root = resolve(new URL('../..', import.meta.url).pathname);
const compiler = resolve(process.argv[2] ?? join(root, 'zig-out/bin/boundary-certify-compile'));
const sourcePaths = process.argv[3] === '--sources' ? process.argv.slice(4) : null;
if (sourcePaths) assert.equal(sourcePaths.length, programNames.length);
const filter = sourcePaths ? undefined : process.argv[3];
const selected = filter ? cases.filter((item) => item.name === filter || item.program === filter) : cases;
assert.ok(selected.length);
const temporary = await mkdtemp(join(tmpdir(), 'boundary-target-machine-'));
try {
  const groups = [];
  for (const name of programNames) {
    const scenarios = selected.filter((item) => item.program === name);
    if (!scenarios.length) continue;
    const sourcePath = sourcePaths?.[programNames.indexOf(name)] ?? join(root, 'zig-out', `source-${name}.json`);
    const source = parseExactJson(await readFile(sourcePath));
    const image = join(temporary, `${name}.bpi2`), witness = join(temporary, `${name}.json`);
    execFileSync(compiler, ['--source', sourcePath, '--image', image, '--witness', witness], { stdio: 'pipe' });
    const paired = parseExactJson(await readFile(witness));
    assert.deepEqual(Buffer.from(paired.source_bytes), await readFile(sourcePath));
    assert.deepEqual(Buffer.from(paired.image_bytes), await readFile(image));
    const program = paired.canonical;
    const constants = program.constants.map(({ schema, bytes }) => exactValueWitness(program, schema, bytes));
    const tests = scenarios.map((test) => {
      const expected = execute(source, test.initial, test.responses, test.cancellations);
      const cursor = { offset: 0 };
      const args = program.functions[program.roots.entry].parameters.map((schema) => decodeValueWitness(program, schema, test.initial, cursor));
      assert.equal(cursor.offset, test.initial.length);
      let response = 0;
      const responses = [];
      for (const [index, event] of expected.trace.entries()) {
        if (event.kind !== 'Requested' || test.cancellations.some((control) => control.at === index && !control.preservesRequest)) continue;
        if (response === test.responses.length) break;
        const effect = program.effects.find((effect) => new TextDecoder().decode(Uint8Array.from(effect.identity)) === event.identity);
        responses.push(exactValueWitness(program, effect.result, test.responses[response++]));
      }
      assert.equal(response, test.responses.length);
      return { name: test.name, args, initial: test.initial, responses, responseBytes: test.responses, cancellations: test.cancellations, expected };
    });
    groups.push({ path: image, constants, tests });
  }
  const witness = join(temporary, 'inputs.json');
  await writeFile(witness, JSON.stringify(groups));
  const output = execFileSync('lake', ['env', 'lean', '--run', '../../tools/v2/target_machine_conformance.lean', witness], {
    cwd: join(root, 'semantics/v2'), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 1_800_000,
  });
  const rows = output.trim().split('\n').filter(Boolean).map((line) => JSON.parse(line));
  assert.equal(rows.length, selected.length);
  const failures = [];
  for (const row of rows) {
    const test = groups.flatMap((group) => group.tests).find((test) => test.name === row.name);
    try {
      assert.ok(!row.error, row.error);
      assert.deepEqual(row.actual, test.expected, row.name);
      console.log(`target machine: ${row.name} (${row.steps} transitions)`);
    } catch (error) {
      failures.push(error);
      console.error(`target machine failed: ${row.name}: ${error.message}`);
    }
  }
  assert.equal(failures.length, 0, `${failures.length} target conformance failures`);
} catch (error) {
  if (error.stdout) process.stderr.write(error.stdout);
  if (error.stderr) process.stderr.write(error.stderr);
  throw error;
} finally {
  await rm(temporary, { recursive: true, force: true });
}
