import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const [probe] = process.argv.slice(2);
assert.ok(probe && process.argv.length === 3, 'usage: snapshot_conformance.mjs <native-probe>');
const root = resolve(new URL('../..', import.meta.url).pathname);
const native = resolve(probe);
const temporary = await mkdtemp(join(tmpdir(), 'boundary-snapshot-'));
const run = (mode, path) => spawnSync(native, [mode, path], { maxBuffer: 4 * 1024 * 1024 });
const rejected = (result, reason) => {
  assert.ok(!result.error, result.error);
  assert.notEqual(result.status, 0, 'invalid snapshot was admitted');
  assert.match(result.stderr.toString(), reason);
  assert.equal(result.stdout.length, 0, 'rejection emitted partial snapshot bytes');
};
try {
  const output = execFileSync('lake', ['env', 'lean', '--run', '../../tools/v2/snapshot_conformance.lean', temporary],
    { cwd: join(root, 'semantics/v2'), encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
  const rows = output.trim().split('\n').map((line) => line.split('\t'));
  const tags = [...new Set(rows.filter(([kind]) => kind === 'tag').map(([, tag]) => tag))].sort();
  const nativeTags = execFileSync(native, ['tags'], { encoding: 'utf8' }).trim().split('\n').sort();
  assert.deepEqual(tags, nativeTags, 'fixture coverage must exhaust the actual production node tags');
  const cases = rows.filter(([kind]) => kind === 'case');
  assert.ok(cases.length > tags.length);
  let malformed = 0;
  for (const [, name, status, alreadyCanonical] of cases) {
    const rawPath = join(temporary, `${name}.raw.pst2`);
    const normalized = run('normalize', rawPath);
    if (status === 'invalid') {
      rejected(normalized, /InvalidReference/);
      rejected(run('admit', rawPath), /InvalidReference/);
    } else {
      assert.equal(status, 'ok');
      const expectedPath = join(temporary, `${name}.canonical.pst2`);
      const expected = await readFile(expectedPath);
      assert.equal(normalized.status, 0, normalized.stderr.toString());
      assert.deepEqual(normalized.stdout, expected, `${name}: full normalized PST2 bytes`);
      const admitted = run('admit', expectedPath);
      assert.equal(admitted.status, 0, admitted.stderr.toString());
      assert.deepEqual(admitted.stdout, expected);
      const rawAdmission = run('admit', rawPath);
      if (alreadyCanonical === 'true') {
        assert.equal(rawAdmission.status, 0, rawAdmission.stderr.toString());
        assert.deepEqual(rawAdmission.stdout, expected);
      } else rejected(rawAdmission, /NonCanonical/);
      if (name === 'cycle') {
        const changed = join(temporary, 'changed.pst2');
        for (const mutation of [expected.subarray(0, expected.length - 1), Buffer.concat([expected, Buffer.from([0])])]) {
          await writeFile(changed, mutation);
          rejected(run('admit', changed), /InvalidLength/);
          malformed++;
        }
      }
    }
    console.log(`snapshot conformance: ${name} passed`);
  }
  assert.equal(malformed, 2);
  console.log(`snapshot conformance: ${cases.length} graphs, all ${tags.length} native node tags, ${malformed} malformed frames passed`);
} finally {
  await rm(temporary, { recursive: true, force: true });
}
