import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { parseExactJson } from '../../tools/v2/exact_json.mjs';
import { sourceAnalysis } from '../../tools/v2/source_analysis.mjs';
import { exactValueWitness, decodeValueWitness } from '../../tools/v2/source_value_witness.mjs';
import { execute, sourceConstructors } from './source_oracle.mjs';

const [compiler, fixtures] = process.argv.slice(2);
assert.ok(compiler && fixtures && process.argv.length === 4);
const root = resolve(new URL('../..', import.meta.url).pathname);
const temporary = await mkdtemp(join(tmpdir(), 'boundary-source-low-level-'));
try {
  const closure = parseExactJson(await readFile(join(fixtures, 'source-lexical.json')));
  closure.variables.push(0);
  closure.values.push({ schema: 2, expression: { primitive: { opcode: 'computation', operands: [1], immediate: 0, failures: [] } } });
  closure.terms.push({ apply: { computation: 7, arguments: [6] } });
  closure.terms.push({ bind: { variable: 3, value: 1, next: 4 } });
  closure.terms.push({ bind: { variable: 2, value: 2, next: 5 } });
  closure.functions[0].body = 6;

  const implicit = parseExactJson(await readFile(join(fixtures, 'source-generator.json')));
  const unit = implicit.schemas.findIndex((schema) => Object.hasOwn(schema, 'unit'));
  const removed = implicit.constants.findIndex((literal) => literal.schema === unit && literal.bytes.length === 0);
  assert.ok(removed >= 0 && implicit.terms.some((term) => Object.hasOwn(term, 'dispose')));
  implicit.constants.splice(removed, 1);
  const remap = (id) => id === removed ? implicit.constants.length : id > removed ? id - 1 : id;
  for (const value of implicit.values) {
    if (Object.hasOwn(value.expression, 'literal')) {
      const id = value.expression.literal;
      value.expression = id === removed
        ? { primitive: { opcode: 'constant', operands: [], immediate: implicit.constants.length, failures: [] } }
        : { literal: remap(id) };
    }
    for (const failure of value.expression.primitive?.failures ?? []) failure.value = remap(failure.value);
  }

  const groups = [];
  const targetGroups = [];
  const scenarios = [
    { name: 'raw-computation', source: closure, initial: [40, 0, 0, 0, 0, 0, 0, 0], responses: [] },
    { name: 'implicit-unit', source: implicit, initial: [], responses: [[]] },
  ];
  for (const test of scenarios) {
    const { name, source, initial, responses } = test;
    const path = join(temporary, `${name}.json`), image = join(temporary, `${name}.bpi2`), witness = join(temporary, `${name}-witness.json`);
    await writeFile(path, JSON.stringify(source));
    execFileSync(resolve(compiler), ['--source', path, '--image', image, '--witness', witness]);
    const candidate = parseExactJson(await readFile(witness));
    const constructors = candidate.lowered.constructors.map(({ function: fn, schema }) => ({ function: fn, schema }));
    assert.deepEqual(constructors, sourceConstructors(source));
    assert.deepEqual(candidate.lowered.constants.map(({schema, bytes}) => [schema, bytes]),
      (name === 'implicit-unit' ? [...source.constants, { schema: unit, bytes: [] }] : source.constants).map(({schema, bytes}) => [schema, bytes]));
    test.expected = execute(source, initial, responses);
    const args = source.functions[source.entry].parameters.map((variable) => exactValueWitness(source, source.variables[variable], initial));
    const responseValues = test.expected.trace.filter((event) => event.kind === 'Requested').map((event, index) => {
      const effect = source.effects.find((effect) => new TextDecoder().decode(Uint8Array.from(effect.identity)) === event.identity);
      return exactValueWitness(source, effect.result, responses[index]);
    });
    groups.push({ path, constructors, facts: sourceAnalysis(source), constants: source.constants.map(({ schema, bytes }) => exactValueWitness(source, schema, bytes)),
      tests: [{ name, args, responses: responseValues, cancellations: [] }] });
    const program = candidate.canonical;
    const cursor = { offset: 0 };
    const targetArgs = program.functions[program.roots.entry].parameters.map((schema) => decodeValueWitness(program, schema, initial, cursor));
    assert.equal(cursor.offset, initial.length);
    const targetResponses = test.expected.trace.filter((event) => event.kind === 'Requested').map((event, index) => {
      const effect = program.effects.find((effect) => new TextDecoder().decode(Uint8Array.from(effect.identity)) === event.identity);
      return exactValueWitness(program, effect.result, responses[index]);
    });
    targetGroups.push({ path: image, constants: program.constants.map(({ schema, bytes }) => exactValueWitness(program, schema, bytes)),
      tests: [{ name, args: targetArgs, initial, responses: targetResponses, responseBytes: responses, cancellations: [] }] });
  }
  const input = join(temporary, 'inputs.json');
  const run = () => execFileSync('lake', ['env', 'lean', '--run', '../../tools/v2/source_machine_conformance.lean', input],
    { cwd: join(root, 'semantics/v2'), encoding: 'utf8', stdio: 'pipe', maxBuffer: 4 * 1024 * 1024 });
  await writeFile(input, JSON.stringify(groups));
  for (const line of run().trim().split('\n')) {
    const row = JSON.parse(line), test = scenarios.find((test) => test.name === row.name);
    assert.ok(!row.error, row.error);
    assert.deepEqual(row.actual, test.expected);
  }
  groups[0].constructors[0].function = 0;
  await writeFile(input, JSON.stringify(groups));
  assert.throws(run, (error) => /source constructor catalog mismatch/.test(String(error.stderr) + String(error.stdout)));
  groups[0].constructors[0].function = 1;
  await writeFile(input, JSON.stringify(groups));
  run();
  const runTarget = () => execFileSync('lake', ['env', 'lean', '--run', '../../tools/v2/target_machine_conformance.lean', input],
    { cwd: join(root, 'semantics/v2'), encoding: 'utf8', stdio: 'pipe', maxBuffer: 4 * 1024 * 1024 });
  await writeFile(input, JSON.stringify(targetGroups));
  for (const line of runTarget().trim().split('\n')) {
    const row = JSON.parse(line), test = scenarios.find((test) => test.name === row.name);
    assert.ok(!row.error, row.error);
    assert.deepEqual(row.actual, test.expected);
  }
  const changed = targetGroups[0].constants.find((value) => value.kind === 'scalar');
  assert.ok(changed);
  const original = changed.value;
  changed.value = String(BigInt(original) + 1n);
  await writeFile(input, JSON.stringify(targetGroups));
  assert.throws(runTarget, (error) => /constant witnesses rejected/.test(String(error.stderr) + String(error.stdout)));
  changed.value = original;
  await writeFile(input, JSON.stringify(targetGroups));
  runTarget();
  console.log('low-level source/target: actual compiler accepts raw computation and implicit unit; three interpreters agree; forged constructor and constant witnesses rejected');
} finally {
  await rm(temporary, { recursive: true, force: true });
}
