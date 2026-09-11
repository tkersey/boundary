import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { parseExactJson } from '../../tools/v2/exact_json.mjs';
import { sourceAnalysis } from '../../tools/v2/source_analysis.mjs';
import { exactValueWitness, decodeValueWitness } from '../../tools/v2/source_value_witness.mjs';
import { cases, programNames } from './semantic_cases.mjs';
import { execute, sourceConstructors } from './source_oracle.mjs';

const root = resolve(new URL('../..', import.meta.url).pathname);
const sourcePaths = process.argv[2] === "--sources" ? process.argv.slice(3) : null;
if (sourcePaths) assert.equal(sourcePaths.length, programNames.length);
const filter = sourcePaths ? undefined : process.argv[2];
const selected = filter ? cases.filter((item) => item.name === filter || item.program === filter) : cases;
assert.ok(selected.length);
const temporary = await mkdtemp(join(tmpdir(), 'boundary-source-machine-'));
try {
  execFileSync('lake', ['build', 'SourceBorrowWitness'], { cwd: join(root, 'semantics/v2'), stdio: 'pipe' });
  const groups = [];
  for (const name of programNames) {
    const scenarios = selected.filter((item) => item.program === name);
    if (!scenarios.length) continue;
    const path = sourcePaths?.[programNames.indexOf(name)] ?? join(root, 'zig-out', `source-${name}.json`);
    const source = parseExactJson(await readFile(path));
    const constants = source.constants.map(({ schema, bytes }) => exactValueWitness(source, schema, bytes));
    const tests = scenarios.map((test) => {
      const expected = execute(source, test.initial, test.responses, test.cancellations);
      const cursor = { offset: 0 };
      const args = source.functions[source.entry].parameters.map((variable) => decodeValueWitness(source, source.variables[variable], test.initial, cursor));
      assert.equal(cursor.offset, test.initial.length);
      let response = 0;
      const responses = [];
      for (const [index, event] of expected.trace.entries()) {
        if (event.kind !== 'Requested' || test.cancellations.some((control) => control.at === index && !control.preservesRequest)) continue;
        if (response === test.responses.length) break;
        const effect = source.effects.find((effect) => new TextDecoder().decode(Uint8Array.from(effect.identity)) === event.identity);
        responses.push(exactValueWitness(source, effect.result, test.responses[response++]));
      }
      assert.equal(response, test.responses.length);
      return { name: test.name, args, initial: test.initial, responses, responseBytes: test.responses,
        cancellations: test.cancellations, checkHandoffCancellation: test.program === 'scoped-reader', expected };
    });
    groups.push({ path, facts: sourceAnalysis(source), constants, constructors: sourceConstructors(source), tests });
  }
  const witness = join(temporary, 'inputs.json');
  await writeFile(witness, JSON.stringify(groups));
  const output = execFileSync('lake', ['env', 'lean', '--run', '../../tools/v2/source_machine_conformance.lean', witness], {
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
      // The client issues one local request; its forwarding clause issues the second.
      if (test.checkHandoffCancellation) assert.equal(row.handoffChecks, 2, 'both owned-body handoffs must be tested');
      console.log(`source machine: ${row.name} (${row.steps} transitions)`);
    } catch (error) {
      failures.push(error);
      console.error(`source machine failed: ${row.name}: ${error.message}`);
    }
  }
  assert.equal(failures.length, 0, `${failures.length} source conformance failures`);
} catch (error) {
  if (error.stdout) process.stderr.write(error.stdout);
  if (error.stderr) process.stderr.write(error.stderr);
  throw error;
} finally {
  await rm(temporary, { recursive: true, force: true });
}
