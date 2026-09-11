import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const bytes = async (path) => [...await readFile(path)];
const literal = (value) => `[${value.join(',')}]`;

// An existing execution module supplies an admitted image and checked hash
// facts. Its declarations remain dependencies of every resulting proof; the
// trust audit must include the exact dependency modules and their sources.
export async function generateRefusals(recordsPath, executionDirectory, outputDirectory) {
  const captured = JSON.parse(await readFile(recordsPath, 'utf8'));
  assert.ok(Array.isArray(captured.records) && captured.records.length, 'refusal.empty_records');
  const bases = new Map();
  for (const name of await readdir(executionDirectory)) {
    if (!/^BoundaryCertificateExecution[0-9a-f]{64}\.json$/.test(name)) continue;
    const base = JSON.parse(await readFile(join(executionDirectory, name), 'utf8'));
    assert.match(base.module, /^BoundaryCertificateExecution[0-9a-f]{64}$/);
    assert.equal(base.claims.length, 1);
    assert.equal(base.claims[0].kind, 'initial-execution');
    assert.ok(!bases.has(base.case), 'refusal.duplicate_image_case');
    bases.set(base.case, base);
  }
  await mkdir(outputDirectory, { recursive: true });
  const certificates = [], seen = new Set();
  for (const row of captured.records) {
    const base = bases.get(row.case);
    assert.ok(base, `refusal.missing_admitted_image: ${row.case}`);
    assert.ok(row.producer === 'native' || row.producer === 'wasm', 'refusal.backend');
    assert.ok(Number.isSafeInteger(row.status) && row.status >= 0, 'refusal.status');
    const record = { backend: row.producer, input: await bytes(row.input), output: await bytes(row.output),
      diagnostic: await bytes(row.error), inputAfter: await bytes(row.inputAfter), status: row.status };
    const subject = { image: base.claims[0].image, record };
    const digest = createHash('sha256').update(JSON.stringify(subject)).digest('hex');
    const module = `BoundaryCertificateRefusal${digest}`;
    assert.ok(!seen.has(module), 'refusal.duplicate_subject'); seen.add(module);
    const path = join(outputDirectory, `${module}.lean`);
    const source = `import BoundaryV2.TargetRejection
import ${base.module}
import Lean.Elab.Tactic.Cbv

set_option Elab.async false
set_option cbv.warning false
set_option cbv.maxSteps 5000000
set_option maxRecDepth 65536
set_option maxHeartbeats 0
attribute [cbv_opaque] BoundaryV2.Profile.SHA256.hash BoundaryV2.Profile.SHA256.hashNumerals
attribute [cbv_opaque] BoundaryV2.Profile.Target.Boundary.responseHeader
attribute [cbv_eval] BoundaryV2.Profile.SHA256.hash_as_numerals

namespace ${module}
open BoundaryV2 BoundaryV2.Profile BoundaryV2.Profile.Target
def record : Boundary.RefusalRecord := {
  backend := .${record.backend}
  input := ${literal(record.input)}
  output := ${literal(record.output)}
  diagnostic := ${literal(record.diagnostic)}
  inputAfter := ${literal(record.inputAfter)}
  status := ${record.status} }
theorem certificate : Boundary.CertifiedRefusal ${base.module}.imageBytes record :=
  Boundary.certify_refusal ${base.module}.image record (by
    cbv
    all_goals (unfold Boundary.responseHeader; decide_cbv))
end ${module}
`;
    await writeFile(path, source);
    const certificate = { module, path, status: 'candidate', case: row.case, name: row.name,
      dependencies: [base.module], claims: [{ name: `${module}.certificate`, kind: 'refusal', ...subject }] };
    await writeFile(join(outputDirectory, `${module}.json`), JSON.stringify(certificate));
    certificates.push(certificate);
  }
  return certificates;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [records, executions, output, ...extra] = process.argv.slice(2);
  assert.ok(records && executions && output && !extra.length,
    'usage: rejection_certify.mjs <refusal-records.json> <execution-certificates> <output-directory>');
  const certificates = await generateRefusals(resolve(records), resolve(executions), resolve(output));
  console.log(`refusal candidates: ${certificates.length} exact physical records`);
}
