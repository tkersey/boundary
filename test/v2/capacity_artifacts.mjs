import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { checkCore, command } from '../../tools/v2/formal.mjs';
import { generateCapacity } from '../../tools/v2/capacity_certify.mjs';

const [formalArgument, invocationArgument, capacityArgument, baseArgument, ...extra] = process.argv.slice(2);
assert.ok(formalArgument && invocationArgument && capacityArgument && baseArgument && !extra.length,
  'usage: capacity_artifacts.mjs <formal-root> <invocations.json> <capacity.json> <execution-certificate.json>');
const root = resolve(formalArgument), observed = new Map();
async function capture(path) {
  const value = await readFile(path);
  if (observed.has(path)) assert.deepEqual(value, observed.get(path), 'capacity.input_changed');
  observed.set(path, value);
  return value;
}
const invocations = JSON.parse(await capture(resolve(invocationArgument)));
const physical = JSON.parse(await capture(resolve(capacityArgument)));
const base = JSON.parse(await capture(resolve(baseArgument)));
assert.match(base.module, /^BoundaryCertificateExecution[0-9a-f]{64}$/);
assert.equal(base.path, join(dirname(resolve(baseArgument)), `${base.module}.lean`));
assert.equal(new Set(invocations.map((row) => row.name)).size, invocations.length);
const group = invocations.find((row) => row.name === base.case);
assert.ok(group, 'capacity.unknown_execution');
const records = [];
for (const transition of group.transitions) records.push({ input: [...await capture(transition.input)],
  output: [...await capture(transition.output)] });
assert.deepEqual(base.claims, [{ name: `${base.module}.certificate`, kind: 'initial-execution',
  image: [...await capture(group.image)], records }]);
assert.equal(physical.format, 'world-v2-transactional-capacity/v1');
assert.deepEqual(physical.rows.map((row) => row.arena).sort(), ['input', 'output', 'working']);
const parent = join(root, '.cache/capacity-artifacts');
await mkdir(parent, { recursive: true });
const directory = await mkdtemp(join(parent, 'run-'));
const source = await capture(base.path);
base.path = join(directory, `${base.module}.lean`);
await writeFile(base.path, source);
const basePath = join(directory, `${base.module}.json`);
await writeFile(basePath, JSON.stringify(base));
const rows = [], subjects = [];
for (const [index, row] of physical.rows.entries()) {
  const copy = { ...row }, data = {};
  for (const role of ['input', 'output', 'callerInputAfter', 'inputAfter', 'retryInput', 'retryOutput', 'retryInputAfter']) {
    if (role === 'inputAfter' && row[role] === null) { data[role] = null; continue; }
    const value = await capture(row[role]);
    data[role] = [...value];
    copy[role] = join(directory, `${index}-${role}.bin`);
    await writeFile(copy[role], value);
  }
  assert.ok(Array.isArray(row.followups), 'capacity.missing_followups');
  copy.followups = [];
  data.followups = [];
  for (const [ordinal, next] of row.followups.entries()) {
    const copied = { ...next }, captured = {};
    for (const role of ['input', 'output', 'inputAfter']) {
      const value = await capture(next[role]);
      captured[role] = [...value];
      copied[role] = join(directory, `${index}-followup-${ordinal}-${role}.bin`);
      await writeFile(copied[role], value);
    }
    copy.followups.push(copied);
    data.followups.push({ invocation: { input: captured.input, output: captured.output },
      inputAfter: captured.inputAfter, prepareStatus: next.prepareStatus, executeStatus: next.executeStatus });
  }
  rows.push(copy);
  subjects.push({ image: base.claims[0].image, capacity: {
    input: data.input, output: data.output, callerInputAfter: data.callerInputAfter,
    guestInputAfter: data.inputAfter, prepareStatus: row.prepareStatus, executeStatus: row.executeStatus,
    retry: { input: data.retryInput, output: data.retryOutput }, retryInputAfter: data.retryInputAfter,
    retryPrepareStatus: row.retryPrepareStatus, retryExecuteStatus: row.retryExecuteStatus,
    followups: data.followups } });
}
const frozenManifest = join(directory, 'capacity.json');
await writeFile(frozenManifest, JSON.stringify({ ...physical, rows }));
const capacity = await generateCapacity(frozenManifest, basePath, directory);
assert.equal(capacity.length, subjects.length);
for (const [index, certificate] of capacity.entries()) {
  assert.deepEqual(certificate.claims, [{ name: `${certificate.module}.certificate`, kind: 'capacity-execution', ...subjects[index] }]);
  assert.deepEqual(certificate.dependencies, [base.module]);
}
const certificates = [base, ...capacity];
const proof = await checkCore(root, { certificates });
console.log('capacity artifacts: 3 completed capacity/retry executions, kernel/trust/fresh replay passed');

async function auditMutation(changedCertificates) {
  const modules = structuredClone(proof.modules);
  for (const certificate of changedCertificates) {
    modules.find((entry) => entry.name === certificate.module).sha256 =
      createHash('sha256').update(await readFile(certificate.path)).digest('hex');
  }
  const inventory = { format: 'boundary.formal-inventory/v1', modules,
    roots: ['Trust', ...modules.filter((entry) => entry.kind === 'certificate').map((entry) => entry.name)],
    claims: changedCertificates.flatMap((certificate) => certificate.claims) };
  const path = join(directory, 'mutation-inventory.json');
  await writeFile(path, JSON.stringify(inventory));
  const result = await command('lake', ['exe', 'boundary-trust', path, join(directory, 'mutation-audit.json')],
    root, { quiet: true });
  assert.equal(result.signal, null);
  assert.notEqual(result.code, 0, 'capacity.mutation_accepted');
  assert.match(result.text, /trust\.claim_type/);
}
async function compile(certificate) {
  const result = await command('lake', ['env', 'lean', '-M', '8192', '-DwarningAsError=true',
    `--root=${dirname(certificate.path)}`, '-o', join(root, '.lake/build/lib/lean', `${certificate.module}.olean`),
    certificate.path], root, { quiet: true });
  assert.equal(result.code, 0, result.text);
  assert.equal(result.signal, null);
}
const original = capacity[0], originalSource = await readFile(original.path, 'utf8');
try {
  const changed = originalSource.replace(/theorem certificate :[\s\S]*?\nend /,
    'theorem certificate : True := .intro\nend ');
  assert.notEqual(changed, originalSource);
  await writeFile(original.path, changed);
  await compile(original);
  await auditMutation(certificates);
} finally {
  await writeFile(original.path, originalSource);
  await compile(original);
}
for (const role of ['image', 'input', 'output', 'callerInputAfter', 'guestInputAfter', 'prepareStatus',
  'executeStatus', 'retry.input', 'retry.output', 'retryInputAfter', 'retryPrepareStatus', 'retryExecuteStatus']) {
  const changed = structuredClone(certificates);
  const claim = changed[1].claims[0];
  if (role === 'guestInputAfter') claim.capacity.guestInputAfter = claim.capacity.guestInputAfter === null ? [] : null;
  else if (role.endsWith('Status')) claim.capacity[role] = (claim.capacity[role] ?? 0) + 1;
  else {
    const value = role === 'image' ? claim.image : role.startsWith('retry.')
      ? claim.capacity.retry[role.slice(6)] : claim.capacity[role];
    if (value.length) value[value.length - 1] ^= 1; else value.push(0);
  }
  await auditMutation(changed);
}
assert.ok(original.claims[0].capacity.followups.length, 'capacity.fixture_missing_continuation');
for (const role of ['input', 'output', 'inputAfter', 'prepareStatus', 'executeStatus', 'missing-final-record']) {
  const changed = structuredClone(certificates), followups = changed[1].claims[0].capacity.followups;
  if (role === 'missing-final-record') followups.pop();
  else if (role.endsWith('Status')) followups[0][role] += 1;
  else {
    const value = role === 'inputAfter' ? followups[0][role] : followups[0].invocation[role];
    if (value.length) value[value.length - 1] ^= 1; else value.push(0);
  }
  await auditMutation(changed);
}
const restored = await checkCore(root, { certificates, quiet: true, reuse: proof });
assert.deepEqual(restored.claims, proof.claims);
for (const [path, value] of observed) assert.deepEqual(await readFile(path), value, 'capacity.input_changed');
console.log('capacity artifacts: false theorem and changed record fields rejected; clean proof and replay restored');
