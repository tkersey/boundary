import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const [probe] = process.argv.slice(2);
assert.ok(probe && process.argv.length === 3, 'usage: protocol_conformance.mjs <native-probe>');
const root = resolve(new URL('../..', import.meta.url).pathname);
const native = resolve(probe);
const temporary = await mkdtemp(join(tmpdir(), 'boundary-protocol-'));
const run = (mode, path) => spawnSync(native, [mode, path], { maxBuffer: 4 * 1024 * 1024 });
const rejected = (result, reason) => {
  assert.ok(!result.error, result.error);
  assert.notEqual(result.status, 0, 'invalid protocol record was admitted');
  assert.match(result.stderr.toString(), reason);
  assert.equal(result.stdout.length, 0, 'rejection emitted partial protocol bytes');
};
try {
  const output = execFileSync('lake', ['env', 'lean', '--run', '../../tools/v2/protocol_conformance.lean', temporary],
    { cwd: join(root, 'semantics/v2'), encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
  const schemaOutput = execFileSync('lake', ['env', 'lean', '--run', '../../tools/v2/schema_conformance.lean', temporary],
    { cwd: join(root, 'semantics/v2'), encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
  const schemaRows = schemaOutput.trim().split('\n').map((line) => line.split('\t'));
  const tags = [...new Set(schemaRows.filter(([kind]) => kind === 'tag').map(([, tag]) => tag))].sort();
  const nativeTags = execFileSync(native, ['schema-tags'], { encoding: 'utf8' }).trim().split('\n').sort();
  assert.deepEqual(tags, nativeTags, 'fixtures must exhaust production schema tags');
  const rows = [...output.trim().split('\n').map((line) => line.split('\t')),
    ...schemaRows.filter(([kind]) => kind !== 'tag')];
  assert.equal(rows.length, 326, 'protocol fixture inventory must not silently shrink');
  const digests = new Map();
  let rejections = 0;
  let malformed = 0;
  for (const [mode, name, status] of rows) {
    const path = join(temporary, `${name}.input`);
    const result = run(mode, path);
    assert.ok(!result.error, result.error);
    if (status === 'reject') {
      rejected(result, /InvalidControl|InvalidUtf8|TrailingBytes|Truncated|NonCanonical|InvalidRequest|InvalidResult|InvalidSchema|InvalidValue/);
      rejections++;
    } else {
      assert.equal(status, 'ok');
      assert.equal(result.status, 0, result.stderr.toString());
      const expected = await readFile(join(temporary, `${name}.expected`));
      assert.deepEqual(result.stdout, expected, `${name}: full bytes differ`);
      if (mode === 'sha256') {
        assert.deepEqual(expected, createHash('sha256').update(await readFile(path)).digest());
      }
      if (mode.endsWith('-identity')) digests.set(name, expected);
      if (mode === 'input' || mode === 'outcome' || mode === 'request') {
        const changed = join(temporary, 'changed.input');
        for (const mutation of [expected.subarray(0, expected.length - 1), Buffer.concat([expected, Buffer.from([0])])]) {
          await writeFile(changed, mutation);
          rejected(run(mode, changed), /InvalidLength/);
          malformed++;
        }
      }
    }
  }
  const requestFields = ['program', 'state', 'contract', 'continuation', 'semantic', 'payload-schema', 'resume-schema', 'payload'];
  for (const field of requestFields) assert.notDeepEqual(digests.get(`request-${field}`), digests.get('request-base'), field);
  assert.deepEqual(digests.get('request-self'), digests.get('request-base'));
  for (const field of ['roots', 'schemas', 'constants', 'effects', 'functions', 'blocks', 'handlers', 'scopes', 'constructors']) {
    assert.notDeepEqual(digests.get(`program-${field}`), digests.get('program-base'), field);
  }
  assert.ok(rejections > 50 && malformed > 50);
  console.log(`protocol conformance: ${rows.length} cases, all ${tags.length} schema tags, ${rejections} semantic rejections, ${malformed} malformed frames passed`);
} finally {
  await rm(temporary, { recursive: true, force: true });
}
