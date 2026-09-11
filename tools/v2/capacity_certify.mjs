import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const bytes = async (path) => [...await readFile(path)];
function literal(value) {
  const parts = [], pending = [];
  const flush = () => {
    if (pending.length) { parts.push(`[${pending.join(',')}]`); pending.length = 0; }
  };
  for (let index = 0; index < value.length;) {
    let end = index + 1;
    while (end < value.length && value[end] === value[index]) end++;
    if (end - index >= 16) {
      flush();
      parts.push(`List.replicate ${end - index} ${value[index]}`);
    } else pending.push(...value.slice(index, end));
    index = end;
  }
  flush();
  return parts.length ? `(${parts.join(' ++ ')})` : '[]';
}
const optional = (value, render) => value === null ? 'none' : `(some ${render(value)})`;

// The successful retry is the first invocation of a separately checked
// execution. Every following invocation is captured from the actual retry
// kernel and must complete the same checked execution. Allocation measurements
// carry no logical bound claim.
export async function generateCapacity(manifestPath, executionPath, outputDirectory) {
  const captured = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert.equal(captured.format, 'world-v2-transactional-capacity/v1');
  assert.ok(Array.isArray(captured.rows) && captured.rows.length, 'capacity.empty_records');
  const base = JSON.parse(await readFile(executionPath, 'utf8'));
  assert.match(base.module, /^BoundaryCertificateExecution[0-9a-f]{64}$/);
  assert.equal(base.claims.length, 1);
  assert.equal(base.claims[0].kind, 'initial-execution');
  assert.ok(base.claims[0].records.length, 'capacity.empty_execution');
  const sameBytes = (left, right) => left.length === right.length && left.every((byte, index) => byte === right[index]);
  const evaluationRecord = (index) => `(${base.module}.evaluationRecords[${index}]?).getD (⟨[], []⟩ : Boundary.PublicInvocation)`;
  const byteTerm = (value) => {
    for (const [index, invocation] of base.claims[0].records.entries()) {
      for (const role of ['input', 'output']) {
        if (sameBytes(value, invocation[role])) return `(${evaluationRecord(index)}).${role}`;
      }
    }
    return literal(value);
  };
  await mkdir(outputDirectory, { recursive: true });
  const certificates = [], seen = new Set();
  for (const row of captured.rows) {
    const record = { input: await bytes(row.input), output: await bytes(row.output),
      callerInputAfter: await bytes(row.callerInputAfter),
      guestInputAfter: row.inputAfter === null ? null : await bytes(row.inputAfter),
      prepareStatus: row.prepareStatus, executeStatus: row.executeStatus,
      retry: { input: await bytes(row.retryInput), output: await bytes(row.retryOutput) },
      retryInputAfter: await bytes(row.retryInputAfter),
      retryPrepareStatus: row.retryPrepareStatus, retryExecuteStatus: row.retryExecuteStatus,
      followups: [] };
    assert.ok(Array.isArray(row.followups), 'capacity.missing_followups');
    for (const next of row.followups) {
      assert.ok(Number.isSafeInteger(next.prepareStatus) && next.prepareStatus >= 0, 'capacity.followup_prepare_status');
      assert.ok(Number.isSafeInteger(next.executeStatus) && next.executeStatus >= 0, 'capacity.followup_execute_status');
      record.followups.push({ invocation: { input: await bytes(next.input), output: await bytes(next.output) },
        inputAfter: await bytes(next.inputAfter), prepareStatus: next.prepareStatus, executeStatus: next.executeStatus });
    }
    for (const field of ['prepareStatus', 'retryPrepareStatus', 'retryExecuteStatus'])
      assert.ok(Number.isSafeInteger(record[field]) && record[field] >= 0, `capacity.${field}`);
    assert.ok(record.executeStatus === null ||
      (Number.isSafeInteger(record.executeStatus) && record.executeStatus >= 0), 'capacity.executeStatus');
    assert.deepEqual(record.retry, base.claims[0].records[0], 'capacity.retry_subject');
    assert.deepEqual(record.followups.map((next) => next.invocation), base.claims[0].records.slice(1),
      'capacity.complete_retry_subject');
    const subject = { image: base.claims[0].image, capacity: record };
    const digest = createHash('sha256').update(JSON.stringify(subject)).digest('hex');
    const module = `BoundaryCertificateCapacity${digest}`;
    assert.ok(!seen.has(module), 'capacity.duplicate_subject'); seen.add(module);
    const path = join(outputDirectory, `${module}.lean`);
    // Exact subject equality above permits sharing large retry byte lists with
    // the execution module. The final theorem still has the full record index.
    const source = `import BoundaryV2.TargetCapacity
import ${base.module}
import Lean.Elab.Tactic.Cbv

set_option Elab.async false
set_option cbv.warning false
set_option cbv.maxSteps 5000000
set_option maxRecDepth 65536
set_option maxHeartbeats 0

namespace ${module}
open BoundaryV2 BoundaryV2.Profile BoundaryV2.Profile.Target
def record : Boundary.CapacityRecord := {
  input := ${byteTerm(record.input)}
  output := ${byteTerm(record.output)}
  callerInputAfter := ${byteTerm(record.callerInputAfter)}
  guestInputAfter := ${optional(record.guestInputAfter, byteTerm)}
  prepareStatus := ${record.prepareStatus}
  executeStatus := ${optional(record.executeStatus, String)}
  retry := ${evaluationRecord(0)}
  retryInputAfter := ${byteTerm(record.retryInputAfter)}
  retryPrepareStatus := ${record.retryPrepareStatus}
  retryExecuteStatus := ${record.retryExecuteStatus}
  followups := [${record.followups.map((next, index) => `{ invocation := ${evaluationRecord(index + 1)}, inputAfter := ${byteTerm(next.inputAfter)}, prepareStatus := ${next.prepareStatus}, executeStatus := ${next.executeStatus} }`).join(',')}] }
theorem envelope : Boundary.capacityEnvelopeValid record = true := by
  have surface : Boundary.capacitySurfaceValid record = true := by decide_cbv
  unfold Boundary.capacityEnvelopeValid
  rw [surface]
  decide +kernel
theorem certificate : Boundary.CertifiedCapacityExecution ${base.module}.imageBytes record :=
  Boundary.certify_capacity_execution record
    (by
      have execution := ${base.module}.certificate
      rw [← ${base.module}.evaluationRecords_exact] at execution
      exact execution)
    envelope (by decide_cbv)
end ${module}
`;
    await writeFile(path, source);
    const certificate = { module, path, status: 'candidate', arena: row.arena,
      dependencies: [base.module], claims: [{ name: `${module}.certificate`, kind: 'capacity-execution', ...subject }] };
    await writeFile(join(outputDirectory, `${module}.json`), JSON.stringify(certificate));
    certificates.push(certificate);
  }
  return certificates;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [manifest, execution, output, ...extra] = process.argv.slice(2);
  assert.ok(manifest && execution && output && !extra.length,
    'usage: capacity_certify.mjs <capacity.json> <execution-certificate.json> <output-directory>');
  const certificates = await generateCapacity(resolve(manifest), resolve(execution), resolve(output));
  console.log(`capacity candidates: ${certificates.length} complete exhaustion and retry records`);
}
