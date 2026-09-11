import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { link, mkdtemp, readFile, readdir, rm, stat, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { programNames } from './semantic_cases.mjs';
import { sourceConstructors } from './source_oracle.mjs';
import { parseExactJson } from '../../tools/v2/exact_json.mjs';

const [compiler, fixtures] = process.argv.slice(2);
assert.ok(compiler && fixtures && process.argv.length === 4,
  'usage: certification_inputs.mjs <paired-compiler> <emitted-fixtures>');
const actual = (await readdir(fixtures)).filter((f) => /^source-.*\.json$/.test(f))
  .map((f) => f.slice(7, -5)).sort();
assert.deepEqual(actual, [...programNames].sort(), 'fixture inventories disagree');
const directory = await mkdtemp(join(tmpdir(), 'boundary-paired-inputs-'));
const image = join(directory, 'program.bpi2');
const witness = join(directory, 'witness.json');
function compile(source) {
  const result = spawnSync(resolve(compiler), ['--source', resolve(source), '--image', image,
    '--witness', witness], { encoding: 'utf8' });
  assert.ifError(result.error);
  assert.equal(result.signal, null, `compiler terminated: ${result.signal}`);
  return result;
}
try {
  for (const name of actual) {
    const source = join(fixtures, `source-${name}.json`);
    const before = await readFile(source);
    const result = compile(source);
    assert.equal(result.status, 0, `${name}: ${result.stderr}`);
    const final = await readFile(image);
    assert.deepEqual(final, await readFile(join(fixtures, `source-${name}.bpi2`)), name);
    // Only byte arrays and format strings are inspected here. Semantic numeric
    // fields in these candidate pass records are left to the exact Lean reader.
    const candidate = parseExactJson(await readFile(witness));
    assert.equal(candidate.format, 'boundary.translation-witness/v1');
    assert.equal(candidate.source_format, 'boundary.staged-source/v1');
    assert.deepEqual(Buffer.from(candidate.source_bytes), before, `${name}: wrong source subject`);
    assert.deepEqual(Buffer.concat([Buffer.from(candidate.decoded_source_bytes), Buffer.from('\n')]), before,
      `${name}: the Module actually supplied to lowering did not round-trip the complete source`);
    assert.deepEqual(Buffer.from(candidate.image_bytes), final, `${name}: wrong image subject`);
    assert.deepEqual(candidate.lowered.constructors.map(({ function: fn, schema }) => ({ function: fn, schema })),
      sourceConstructors(parseExactJson(before)), `${name}: source constructor order`);
    for (const phase of ['lowered', 'custody', 'direct', 'canonical']) {
      assert.ok(candidate[phase]?.blocks?.length, `${name}: absent ${phase} evidence`);
    }
    assert.deepEqual(await readFile(source), before, `${name}: source was modified`);
  }
  const lexical = await readFile(join(fixtures, 'source-lexical.json'), 'utf8');
  const sparseModule = parseExactJson(Buffer.from(lexical));
  delete sparseModule.resources;
  for (const fn of sparseModule.functions) { delete fn.effects; delete fn.regions; }
  for (const value of sparseModule.values) {
    if (value.expression.primitive?.immediate === 0) delete value.expression.primitive.immediate;
  }
  const sparseSource = join(directory, 'defaulted-source.json');
  await writeFile(sparseSource, JSON.stringify(sparseModule, null, 2));
  assert.equal(compile(sparseSource).status, 0, 'existing optional defaults must remain accepted');
  const defaulted = parseExactJson(await readFile(witness));
  assert.deepEqual(Buffer.concat([Buffer.from(defaulted.decoded_source_bytes), Buffer.from('\n')]), Buffer.from(lexical));
  assert.deepEqual(await readFile(image), await readFile(join(fixtures, 'source-lexical.bpi2')));
  const badSource = join(directory, 'bad.json');
  const badCases = [
    lexical.replace('"entry":0', '"entry":0,"entry":0'),
    lexical.replace('"entry":0', '"entry":0,"unknown":0'),
    lexical.replace('"entry":0', '"entry":"0"'),
    lexical.replace('"entry":0', '"entry":0e0'),
    lexical.replace('"entry":0', '"entry":0.0'),
    lexical.replace('"entry":0', '"entry":18446744073709551616'),
    lexical.replace('"entry":0,', ''),
    lexical.replace('"use":"reusable"', '"use":0'),
    `${lexical} {}`,
  ];
  for (const bad of badCases) {
    assert.notEqual(bad, lexical, 'negative input mutation did not apply');
    await writeFile(badSource, bad);
    await rm(image, { force: true }); await rm(witness, { force: true });
    assert.notEqual(compile(badSource).status, 0, 'malformed source accepted');
    await assert.rejects(readFile(witness), { code: 'ENOENT' });
  }
  const aliasSource = join(directory, 'alias.json');
  await writeFile(aliasSource, lexical);
  const aliased = spawnSync(resolve(compiler), ['--source', aliasSource, '--image',
    `${directory}/./alias.json`, '--witness', witness], { encoding: 'utf8' });
  assert.notEqual(aliased.status, 0, 'normalized output alias must reject');
  assert.match(aliased.stderr, /AliasedOutputs/);
  assert.equal(await readFile(aliasSource, 'utf8'), lexical);
  await rm(image, { force: true });
  await link(aliasSource, image);
  assert.equal(compile(aliasSource).status, 0, 'atomic replacement may detach an output hard link');
  assert.equal(await readFile(aliasSource, 'utf8'), lexical, 'output must not overwrite the input inode');
  const caseSource = join(directory, 'Source.json');
  const caseImage = join(directory, 'source.json');
  await writeFile(caseSource, lexical);
  const caseInsensitive = await stat(caseImage).then(() => true, (error) => {
    if (error.code !== 'ENOENT') throw error;
    return false;
  });
  if (!caseInsensitive) await symlink(caseSource, caseImage);
  const caseAlias = spawnSync(resolve(compiler), ['--source', caseSource, '--image', caseImage,
    '--witness', witness], { encoding: 'utf8' });
  assert.notEqual(caseAlias.status, 0, 'a filesystem-resolved input alias must reject');
  assert.match(caseAlias.stderr, /AliasedOutputs/);
  assert.equal(await readFile(caseSource, 'utf8'), lexical, 'an input alias must not destroy the source');
  const newImage = join(directory, 'NewOutput.bpi2'), newWitness = join(directory, 'newoutput.bpi2');
  const outputAlias = spawnSync(resolve(compiler), ['--source', aliasSource, '--image', newImage,
    '--witness', newWitness], { encoding: 'utf8' });
  if (caseInsensitive) {
    assert.notEqual(outputAlias.status, 0, 'new output aliases must not report a successful pair');
    assert.match(outputAlias.stderr, /AliasedOutputs/);
  } else {
    assert.equal(outputAlias.status, 0, outputAlias.stderr);
    assert.equal(parseExactJson(await readFile(newWitness)).format, 'boundary.translation-witness/v1');
  }
  assert.equal(await readFile(aliasSource, 'utf8'), lexical);
  console.log(`paired compilation: ${actual.length} source/image subjects and all four pass snapshots match; ${badCases.length} malformed inputs rejected`);
} finally { await rm(directory, { recursive: true, force: true }); }
