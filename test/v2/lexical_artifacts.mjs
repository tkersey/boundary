import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { certifyArtifacts, prepareArtifactModule } from '../../tools/v2/artifact_certify.mjs';
import { parseExactJson } from '../../tools/v2/exact_json.mjs';
import { checkCore } from '../../tools/v2/formal.mjs';
import { execute } from './source_oracle.mjs';

const [compiler, formalRoot, fixtures] = process.argv.slice(2).map((path) => resolve(path));
assert.ok(compiler && formalRoot && fixtures && process.argv.length === 5,
  'usage: lexical_artifacts.mjs <paired-compiler> <formal-root> <fixture-directory>');
const directory = await mkdtemp(join(tmpdir(), 'boundary-lexical-'));
const scalar = (value) => [...Buffer.from(BigInt(value).toString(16).padStart(16, '0'), 'hex')].reverse();
const compile = (input) => {
  const result = spawnSync(compiler, ['--source', input.source, '--image', input.image,
    '--witness', input.witness], { encoding: 'utf8' });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
};
try {
  const originalSource = await readFile(join(fixtures, 'source-lexical.json'));
  const inputs = [];
  const maximum = (1n << 64n) - 1n;
  for (const [index, offset] of [2n, 0n, maximum].entries()) {
    const source = parseExactJson(originalSource);
    source.constants[1].bytes = scalar(offset);
    const input = { source: join(directory, `${index}.json`), image: join(directory, `${index}.bpi2`),
      witness: join(directory, `${index}.witness.json`) };
    await writeFile(input.source, `${JSON.stringify(source)}\n`);
    compile(input);
    if (index === 0) {
      assert.deepEqual(await readFile(input.source), originalSource);
      assert.deepEqual(await readFile(input.image), await readFile(join(fixtures, 'source-lexical.bpi2')));
    }
    // Independent source interpretation exercises both arithmetic outcomes;
    // the Lean theorem quantifies over every admitted input.
    for (const argument of new Set([0n, 1n, maximum - offset, maximum])) {
      const observation = execute(source, scalar(argument));
      const overflow = argument + offset > maximum;
      assert.equal(observation.kind, overflow ? 'Failed' : 'Completed');
      assert.deepEqual(observation.value, overflow ? [] : scalar(argument + offset));
      assert.deepEqual(observation.trace, []);
    }
    inputs.push(input);
  }
  const proof = await certifyArtifacts(formalRoot, inputs, { fragment: 'lexical' });
  const original = await readFile(proof.path, 'utf8');
  try {
    await writeFile(proof.path, original.replace(/theorem certificate0[^\n]*\n[^\n]*\n/,
      'theorem certificate0 : True := .intro\n'));
    await assert.rejects(checkCore(formalRoot, { replay: false, quiet: true, certificates: [proof] }),
      /trust\.claim_type/, 'lexical claim kind must bind the complete proposition');
  } finally { await writeFile(proof.path, original); }

  const changedSource = parseExactJson(originalSource);
  changedSource.values[1].expression.variable = 1; // lambda now adds its argument twice
  const changed = { source: join(directory, 'wrong-capture.json'), image: join(directory, 'wrong-capture.bpi2'),
    witness: join(directory, 'wrong-capture.witness.json') };
  await writeFile(changed.source, `${JSON.stringify(changedSource)}\n`);
  compile(changed);
  assert.notDeepEqual(await readFile(changed.image), await readFile(inputs[0].image));
  const witness = parseExactJson(await readFile(changed.witness));
  witness.source_bytes = [...originalSource];
  await writeFile(changed.witness, JSON.stringify(witness));
  changed.source = inputs[0].source;
  const mutant = await prepareArtifactModule(formalRoot, [changed], 'lexical');
  await assert.rejects(checkCore(formalRoot, { replay: false, quiet: true, certificates: [mutant] }),
    /evaluated to false|decide.*failed|failed to synthesize|tactic.*failed|kernel.*failed/i,
    'a different captured variable must not certify as the original source');
  await checkCore(formalRoot, { replay: false, quiet: true, certificates: [proof] });
  console.log('lexical artifacts: baseline and two offset variants have exact-byte all-input closure/overflow proofs; altered capture and false claim rejected');
} finally { await rm(directory, { recursive: true, force: true }); }
