import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { certifyArtifacts, prepareArtifactModule } from '../../tools/v2/artifact_certify.mjs';
import { checkCore } from '../../tools/v2/formal.mjs';

const [compiler, formalRoot] = process.argv.slice(2).map((path) => resolve(path));
assert.ok(compiler && formalRoot && process.argv.length === 4,
  'usage: projection_artifacts.mjs <paired-compiler> <formal-root>');
const directory = await mkdtemp(join(tmpdir(), 'boundary-projection-'));
function source(arity, selection) {
  const parameter = Object.hasOwn(selection, 'parameter');
  const literal = parameter ? [] : [...Buffer.from(BigInt(selection.literal).toString(16).padStart(16, '0'), 'hex')].reverse();
  return { entry: 0, failure: 1, schemas: [{ u64: {} }, { unit: {} }],
    constants: parameter ? [] : [{ schema: 0, bytes: literal }], effects: [], handlers: [],
    region_count: 0, resources: [], variables: Array(arity).fill(0),
    values: [{ schema: 0, expression: parameter ? { variable: selection.parameter } : { literal: 0 } }],
    terms: [{ value: 0 }], functions: [{ parameters: Array.from({ length: arity }, (_, i) => i),
      result: 0, effects: [], regions: [], body: 0 }] };
}
try {
  const cases = [[1, { parameter: 0 }], [3, { parameter: 1 }], [7, { parameter: 6 }],
    [0, { literal: 42n }], [2, { literal: 0n }], [3, { literal: (1n << 64n) - 1n }]];
  const inputs = [];
  for (const [index, [arity, selection]] of cases.entries()) {
    const input = { source: join(directory, `${index}.json`), image: join(directory, `${index}.bpi2`),
      witness: join(directory, `${index}.witness.json`) };
    await writeFile(input.source, `${JSON.stringify(source(arity, selection))}\n`);
    const result = spawnSync(compiler, ['--source', input.source, '--image', input.image,
      '--witness', input.witness], { encoding: 'utf8' });
    assert.ifError(result.error); assert.equal(result.status, 0, result.stderr);
    inputs.push(input);
  }
  const proof = await certifyArtifacts(formalRoot, inputs);
  const original = await readFile(proof.path, 'utf8');
  const wrongClaims = [
    ['True', 'theorem certificate0 : True := .intro\n', /trust\.claim_type/],
    ['restricted', 'theorem certificate0 (arguments : List Nat) (_restricted : arguments = [0]) :\n' +
      '    BoundaryV2.ProjectionArtifact.sourceMeaning candidate0 arguments =\n' +
      '      BoundaryV2.ProjectionArtifact.targetMeaning (BoundaryV2.ProjectionArtifact.targetFor candidate0) arguments :=\n' +
      '  BoundaryV2.ProjectionArtifact.all_input_correspondence candidate0 arguments\n', /trust\.claim_type/],
  ];
  try {
    for (const [name, declaration, diagnostic] of wrongClaims) {
      const wrongType = original.replace(/theorem certificate0[^\n]*\n[^\n]*\n/, declaration);
      assert.notEqual(wrongType, original);
      await writeFile(proof.path, wrongType);
      await assert.rejects(checkCore(formalRoot, { replay: false, quiet: true, certificates: [proof] }),
        diagnostic, `a ${name} theorem must not acquire artifact status`);
    }
    await writeFile(proof.path, original.replace('decide +kernel', 'decide +native'));
    await assert.rejects(checkCore(formalRoot, { replay: false, quiet: true, certificates: [proof] }),
      /trust\.(forbidden_axiom|project_axiom)/, 'native computation is not proof authority');
  } finally { await writeFile(proof.path, original); }
  const stale = structuredClone(proof);
  stale.claims[0].image[stale.claims[0].image.length - 1] ^= 1;
  await assert.rejects(checkCore(formalRoot, { replay: false, quiet: true, certificates: [stale] }),
    /trust\.claim_type/, 'an old theorem cannot bind changed image bytes');
  const missing = structuredClone(proof);
  missing.claims[0].name = `${proof.module}.absentDependency`;
  await assert.rejects(checkCore(formalRoot, { replay: false, quiet: true, certificates: [missing] }),
    /trust\.missing_claim/, 'missing certificate declarations cannot pass');
  const modified = inputs[3];
  const bytes = await readFile(modified.image);
  const literal = bytes.indexOf(Buffer.from([42, 0, 0, 0, 0, 0, 0, 0]));
  assert.ok(literal >= 0, 'constant mutation missed its target');
  const changed = Buffer.from(bytes); changed[literal] = 43;
  await writeFile(modified.image, changed);
  const witness = JSON.parse(await readFile(modified.witness, 'utf8'));
  witness.image_bytes = [...changed];
  await writeFile(modified.witness, JSON.stringify(witness));
  const mutant = await prepareArtifactModule(formalRoot, [modified]);
  await assert.rejects(checkCore(formalRoot, { replay: false, quiet: true, certificates: [mutant] }),
    /evaluated to false|decide.*failed|failed to synthesize|tactic.*failed|kernel.*failed/i,
    'changed final constant must fail the semantic artifact relation');
  await writeFile(modified.image, bytes);
  witness.image_bytes = [...bytes];
  await writeFile(modified.witness, JSON.stringify(witness));
  await checkCore(formalRoot, { replay: false, quiet: true, certificates: [proof] });
  console.log('projection artifacts: six complete source/final-image pairs have all-input kernel proofs; false claim type and changed final bytes rejected');
} finally { await rm(directory, { recursive: true, force: true }); }
