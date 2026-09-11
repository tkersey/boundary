// Development fragments. Their exact claim kinds remain distinct from the
// complete BPI2 profile guarantee, which these rules do not establish.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { checkCore } from './formal.mjs';
import { parseExactJson } from './exact_json.mjs';

function natural(value) {
  if (typeof value === 'bigint' && value >= 0n) return value.toString();
  assert.ok(Number.isSafeInteger(value) && value >= 0, 'projection.invalid_natural');
  return String(value);
}

function candidate(bytes, fragment) {
  const source = parseExactJson(bytes);
  if (fragment === 'lexical') {
    const bytes = source.constants?.[1]?.bytes;
    assert.equal(bytes?.length, 8, 'lexical.invalid_literal');
    let value = 0n;
    for (let index = 7; index >= 0; index--) {
      assert.ok(Number.isInteger(bytes[index]) && bytes[index] >= 0 && bytes[index] < 256);
      value = (value << 8n) | BigInt(bytes[index]);
    }
    return value.toString();
  }
  assert.equal(source.functions?.length, 1, 'projection.unsupported_functions');
  assert.equal(source.values?.length, 1, 'projection.unsupported_values');
  assert.equal(source.terms?.length, 1, 'projection.unsupported_terms');
  const arity = source.functions[0].parameters.length;
  const expression = source.values[0].expression;
  if (Object.hasOwn(expression, 'variable')) {
    return { arity: natural(arity), selection: `.parameter ${natural(expression.variable)}` };
  }
  assert.equal(expression.literal, 0, 'projection.unsupported_expression');
  assert.equal(source.constants?.length, 1, 'projection.unsupported_constants');
  const literal = source.constants[0].bytes;
  assert.equal(literal.length, 8, 'projection.invalid_literal');
  let value = 0n;
  for (let index = 7; index >= 0; index--) {
    assert.ok(Number.isInteger(literal[index]) && literal[index] >= 0 && literal[index] < 256);
    value = (value << 8n) | BigInt(literal[index]);
  }
  return { arity: natural(arity), selection: `.literal ${value}` };
}

export async function prepareArtifactModule(root, inputs, fragment = 'projection') {
  assert.ok(['projection', 'lexical'].includes(fragment), 'artifact.unsupported_fragment');
  const namespace = fragment === 'projection' ? 'BoundaryV2.ProjectionArtifact' : 'BoundaryV2.LexicalArtifact';
  root = resolve(root);
  assert.ok(inputs.length, 'projection.empty_subjects');
  const subjects = [];
  for (const input of inputs) {
    const source = await readFile(input.source);
    const image = await readFile(input.image);
    const witness = parseExactJson(await readFile(input.witness));
    assert.equal(witness.format, 'boundary.translation-witness/v1');
    assert.equal(witness.source_format, 'boundary.staged-source/v1');
    assert.deepEqual(witness.source_bytes, [...source], 'projection.witness_source_mismatch');
    assert.deepEqual(witness.image_bytes, [...image], 'projection.witness_image_mismatch');
    subjects.push({ source, image, candidate: candidate(source, fragment) });
  }
  const digest = createHash('sha256');
  digest.update(fragment);
  for (const subject of subjects) {
    digest.update(String(subject.source.length)).update(':').update(subject.source);
    digest.update(String(subject.image.length)).update(':').update(subject.image);
  }
  const module = `BoundaryCertificate${digest.digest('hex')}`;
  let code = `import ${namespace}\n\nnamespace ${module}\n`;
  const claims = [];
  for (const [index, subject] of subjects.entries()) {
    const sourceName = `source${index}`, imageName = `image${index}`, candidateName = `candidate${index}`;
    code += `\ndef ${sourceName} : BoundaryV2.ProjectionArtifact.Bytes := [${[...subject.source]}]\n`;
    code += `def ${imageName} : BoundaryV2.ProjectionArtifact.Bytes := [${[...subject.image]}]\n`;
    code += fragment === 'projection'
      ? `def ${candidateName} : ${namespace}.Source := { arity := ${subject.candidate.arity}, selection := ${subject.candidate.selection} }\n`
      : `def ${candidateName} : Nat := ${subject.candidate}\n`;
    code += `theorem certificate${index} : ${namespace}.Certified ${sourceName} ${imageName} :=\n`;
    code += `  ${namespace}.check_sound _ _ ${candidateName} (by decide +kernel)\n`;
    claims.push({ name: `${module}.certificate${index}`, kind: `${fragment}-artifact`,
      source: [...subject.source], image: [...subject.image] });
  }
  code += `\nend ${module}\n`;
  const directory = join(root, '.cache/certification');
  await mkdir(directory, { recursive: true });
  const path = join(directory, `${module}.lean`);
  await writeFile(path, code);
  return { module, path, claims };
}

export async function certifyArtifacts(root, inputs, { fragment = 'projection', ...options } = {}) {
  const certificate = await prepareArtifactModule(root, inputs, fragment);
  await checkCore(root, { ...options, certificates: [certificate] });
  // IO binding check: the proof and its record concern these frozen bytes.
  for (const [index, input] of inputs.entries()) {
    assert.deepEqual([...await readFile(input.source)], certificate.claims[index].source,
      'projection.source_changed');
    assert.deepEqual([...await readFile(input.image)], certificate.claims[index].image,
      'projection.image_changed');
  }
  return certificate;
}
