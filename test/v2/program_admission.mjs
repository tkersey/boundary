import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { parseExactJson } from '../../tools/v2/exact_json.mjs';
import { programNames } from './semantic_cases.mjs';
import { sourceAnalysis } from '../../tools/v2/source_analysis.mjs';
import { exactValueWitness } from '../../tools/v2/source_value_witness.mjs';

const root = resolve(new URL('../..', import.meta.url).pathname);
const [probePath, compilerPath, borrowEmitterPath, ...sourcePaths] = process.argv.slice(2);
const probe = resolve(probePath ?? join(root, 'zig-out/bin/boundary-admission-probe'));
const compiler = resolve(compilerPath ?? join(root, 'zig-out/bin/boundary-certify-compile'));
const borrowEmitter = resolve(borrowEmitterPath ?? join(root, 'zig-out/bin/borrow-returns'));
if (sourcePaths.length) assert.equal(sourcePaths.length, programNames.length);
const temporary = await mkdtemp(join(tmpdir(), 'boundary-program-admission-'));
const primitiveSource = (opcode, schemas, parameters, result) => ({
  entry: 0, failure: 0, schemas, constants: [], effects: [], handlers: [], region_count: 0, resources: [],
  variables: parameters,
  values: [...parameters.map((schema, variable) => ({ schema, expression: { variable } })),
    { schema: result, expression: { primitive: { opcode, operands: parameters.map((_, index) => index), immediate: 0, failures: [] } } }],
  terms: [{ value: parameters.length }],
  functions: [{ parameters: parameters.map((_, index) => index), result, effects: [], regions: [], body: 0 }],
});
const extraPrograms = [
  ...['integer_bit_and', 'integer_bit_or', 'integer_bit_xor'].map((opcode) =>
    [opcode, primitiveSource(opcode, [{ unit: {} }, { u64: {} }], [1, 1], 1)]),
  ['enum_tag', primitiveSource('enum_tag', [{ unit: {} }, { enumeration: [0, 7, 4294967295] }, { u32: {} }], [1], 2)],
  ['blob_byte', primitiveSource('blob_byte', [{ unit: {} }, { bytes: {} }, { u64: {} }, { u8: {} }, { sum: [0, 3] }], [1, 2], 4)],
];
try {
  execFileSync('lake', ['build', 'BorrowWitness'], { cwd: join(root, 'semantics/v2'), stdio: 'pipe' });
  const images = [];
  const sourceGroups = [];
  const sources = programNames.map((name, index) => [name, sourcePaths[index] ?? join(root, 'zig-out', `source-${name}.json`), true]);
  for (const [name, module] of extraPrograms) {
    const path = join(temporary, `additional-${name}.json`);
    await writeFile(path, JSON.stringify(module));
    sources.push([`additional-${name}`, path, true]);
  }
  const emitted = spawnSync(borrowEmitter, ['--sources'], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  assert.ok(!emitted.error, emitted.error);
  assert.equal(emitted.status, 0, emitted.stderr);
  assert.equal(emitted.stderr, '');
  const borrowSources = emitted.stdout.trim().split('\n').map((line) => parseExactJson(Buffer.from(line)));
  assert.equal(borrowSources.length, 24);
  const borrowKeys = new Set();
  for (const item of borrowSources) {
    assert.ok(['state', 'body', 'pair'].includes(item.from));
    for (const field of ['initial', 'younger', 'delegated']) assert.equal(typeof item[field], 'boolean');
    const name = `return-${item.from}-${item.initial}-${item.younger}-${item.delegated}`;
    assert.ok(!borrowKeys.has(name));
    borrowKeys.add(name);
    const path = join(temporary, `${name}.json`);
    await writeFile(path, JSON.stringify(item.source));
    sources.push([name, path, !item.younger]);
  }
  let unsafeBorrowSources = 0;
  for (const [name, source, valid] of sources) {
    const image = join(temporary, `${name}.bpi2`);
    const witness = join(temporary, `${name}-witness.json`);
    const compiled = spawnSync(compiler, ['--source', source, '--image', image, '--witness', witness], { maxBuffer: 16 * 1024 * 1024 });
    assert.ok(!compiled.error, compiled.error);
    if (!valid) {
      assert.notEqual(compiled.status, 0, `${name}: younger borrow escaped`);
      assert.match(compiled.stderr.toString(), /InvalidOwnership/);
      await assert.rejects(readFile(image), { code: 'ENOENT' });
      await assert.rejects(readFile(witness), { code: 'ENOENT' });
      unsafeBorrowSources++;
      continue;
    }
    assert.equal(compiled.status, 0, `${name}: ${compiled.stderr}`);
    assert.equal(compiled.stderr.length, 0, `${name}: successful compiler emitted diagnostics`);
    const paired = parseExactJson(await readFile(witness));
    assert.deepEqual(Buffer.from(paired.source_bytes), await readFile(source));
    assert.deepEqual(Buffer.from(paired.image_bytes), await readFile(image));
    const module = parseExactJson(await readFile(source));
    sourceGroups.push({ path: source, facts: sourceAnalysis(module),
      constants: module.constants.map(({ schema, bytes }) => exactValueWitness(module, schema, bytes)), tests: [],
      ...(name === 'borrow-operands' ? { authorityBudgetMs: 5000 } : {}) });
    images.push(image);
  }
  assert.equal(unsafeBorrowSources, 12);
  const sourceWitness = join(temporary, 'source-admission.json');
  await writeFile(sourceWitness, JSON.stringify(sourceGroups));
  const sourceOutput = execFileSync('lake', ['env', 'lean', '--run', '../../tools/v2/source_machine_conformance.lean', sourceWitness], {
    cwd: join(root, 'semantics/v2'), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 1_800_000,
  });
  assert.equal(sourceOutput, '');
  console.log(`source admission: ${sourceGroups.length} emitted sources, declaration, primitive, resource authority, control and mutation checks passed`);
  const output = execFileSync('lake', ['env', 'lean', '--run', '../../tools/v2/program_admission_conformance.lean', temporary, ...images], {
    cwd: join(root, 'semantics/v2'), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 1_800_000,
  });
  const rows = output.trim().split('\n').map((line) => line.split('\t'));
  const opcodes = rows.filter(([tag]) => tag === 'opcode').map(([, name]) => name).sort();
  const nativeOpcodes = execFileSync(probe, ['opcodes'], { encoding: 'utf8' }).trim().split('\n').sort();
  const missingOpcodes = nativeOpcodes.filter((opcode) => !opcodes.includes(opcode));
  assert.deepEqual(missingOpcodes, [], 'emitted programs must exercise every instruction admission branch');
  let accepted = 0, rejected = 0;
  const borrowFiles = [];
  for (const [kind, name, expected] of rows) {
    if (kind !== 'case') continue;
    const input = join(temporary, `${name}.program`);
    const result = spawnSync(probe, ['program', input], { maxBuffer: 64 * 1024 * 1024, timeout: 120_000 });
    assert.ok(!result.error, result.error);
    if (expected === 'ok') {
      assert.equal(result.status, 0, `${name}: ${result.stderr}`);
      assert.deepEqual(result.stdout, await readFile(input), `${name}: exact program bytes changed`);
      const exported = execFileSync(probe, ['borrow', input], { maxBuffer: 64 * 1024 * 1024, timeout: 120_000 });
      const data = parseExactJson(exported);
      assert.deepEqual(Buffer.from(data.program_bytes), await readFile(input), `${name}: witness subject mismatch`);
      assert.ok(Array.isArray(data.paths) && Array.isArray(data.queries) && Array.isArray(data.requirements));
      const borrowFile = join(temporary, `${name}.borrow.json`);
      await writeFile(borrowFile, exported);
      borrowFiles.push(borrowFile);
      accepted++;
    } else {
      assert.equal(expected, 'reject');
      assert.notEqual(result.status, 0, `${name}: invalid program admitted`);
      assert.equal(result.stdout.length, 0, `${name}: rejection emitted partial bytes`);
      assert.match(result.stderr.toString(), /InvalidProgram|InvalidReference|InvalidSchema|TypeMismatch/);
      rejected++;
    }
  }
  assert.equal(accepted, programNames.length + extraPrograms.length + 12);
  assert.equal(rejected, accepted + 2 * nativeOpcodes.length);
  const borrowOutput = execFileSync('lake', ['env', 'lean', '--run', '../../tools/v2/borrow_conformance.lean', ...borrowFiles], {
    cwd: join(root, 'semantics/v2'), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 1_800_000,
  });
  const borrowRows = borrowOutput.trim().split('\n').map((line) => line.split('\t'));
  assert.equal(borrowRows.length, accepted);
  assert.ok(borrowRows.every(([kind]) => kind === 'borrow'));
  const supportMutations = borrowRows.reduce((count, row) => count + Number(row[4]), 0);
  const subjectMutations = borrowRows.reduce((count, row) => count + Number(row[5]), 0);
  const sourceMutations = borrowRows.reduce((count, row) => count + Number(row[6]), 0);
  const constraintMutations = borrowRows.reduce((count, row) => count + Number(row[7]), 0);
  assert.ok(supportMutations > 10 && subjectMutations > 10,
    `borrow mutation coverage must remain substantive: ${supportMutations} support, ${subjectMutations} subject`);
  assert.ok(sourceMutations > 10 && constraintMutations > 10,
    `borrow semantic mutation coverage: ${sourceMutations} source, ${constraintMutations} constraint`);
  const canonicalOutput = execFileSync('lake', ['env', 'lean', '--run', '../../tools/v2/program_canonical_conformance.lean', temporary, ...images], {
    cwd: join(root, 'semantics/v2'), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 1_800_000,
  });
  const canonicalRows = canonicalOutput.trim().split('\n').map((line) => line.split('\t'));
  const shiftedKinds = canonicalRows.filter(([tag]) => tag === 'shift').map(([, kind]) => kind).sort();
  assert.deepEqual(shiftedKinds, ['schema', 'constant', 'effect', 'function', 'block', 'handler', 'capture', 'region', 'resource', 'constructor'].sort());
  const permutations = canonicalRows.filter(([tag]) => tag === 'permutation');
  assert.deepEqual(permutations.map(([, kind]) => kind).sort(), shiftedKinds, 'all catalog kinds must be permuted');
  const interning = canonicalRows.filter(([tag]) => tag === 'interning');
  assert.equal(interning.length, 1);
  assert.ok(Number(interning[0][1]) >= 20, 'full-byte constant interning coverage');
  assert.equal(Number(interning[0][2]), 1, 'equal-name nominal effect coverage');
  let canonicalAccepted = 0, canonicalRejected = 0;
  for (const [tag, name, expected] of canonicalRows) {
    if (tag !== 'canonical') continue;
    const input = join(temporary, `${name}.program`);
    // These mutations are valid programs. Rejection must be canonicality,
    // independently of typing and ownership admission.
    const admitted = execFileSync(probe, ['program', input], { maxBuffer: 64 * 1024 * 1024, timeout: 120_000 });
    assert.deepEqual(admitted, await readFile(input));
    const normalized = execFileSync(probe, ['normalize', input], { maxBuffer: 64 * 1024 * 1024, timeout: 120_000 });
    assert.deepEqual(normalized, await readFile(join(temporary, `${name}.normalized`)), `${name}: full normalized records differ`);
    for (const [mode, path] of [['canonical', input], ['image', join(temporary, `${name}.bpi2`)]]) {
      const result = spawnSync(probe, [mode, path], { maxBuffer: 64 * 1024 * 1024, timeout: 120_000 });
      assert.ok(!result.error, result.error);
      if (expected === 'ok') {
        assert.equal(result.status, 0, `${name}/${mode}: ${result.stderr}`);
        assert.equal(result.stderr.length, 0);
        assert.deepEqual(result.stdout, await readFile(path));
      } else {
        assert.equal(expected, 'reject');
        assert.notEqual(result.status, 0, `${name}/${mode}: noncanonical input accepted`);
        assert.equal(result.stdout.length, 0);
        assert.match(result.stderr.toString(), /NonCanonical/);
      }
    }
    if (expected === 'ok') canonicalAccepted++; else canonicalRejected++;
  }
  assert.equal(canonicalAccepted, accepted + 1);
  assert.equal(canonicalRejected, accepted + shiftedKinds.length + permutations.length + Number(interning[0][1]));
  console.log(`program admission: ${accepted} emitted programs, all ${opcodes.length} opcodes, ${rejected} semantic rejections passed`);
  console.log(`borrow closure: ${borrowRows.length} native analyses rechecked, ${accepted} missing requirement, ${supportMutations} missing support, ${subjectMutations} changed subject mutations rejected`);
  console.log(`borrow semantic mutations: ${sourceMutations} missing source dependencies and ${constraintMutations} missing ownership constraints rejected`);
  console.log(`borrow source regressions: ${unsafeBorrowSources} younger-reference programs rejected without publishing outputs`);
  console.log(`canonical images: ${canonicalAccepted} exact round trips, ${canonicalRejected} noncanonical programs rejected, all 10 catalog kinds shifted, ${permutations.length} catalog kinds permuted; complete normalized bytes agree`);
} catch (error) {
  if (error.stdout) process.stderr.write(error.stdout);
  if (error.stderr) process.stderr.write(error.stderr);
  throw error;
} finally {
  await rm(temporary, { recursive: true, force: true });
}
