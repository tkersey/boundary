import test from 'node:test';
import assert from 'node:assert/strict';
import { gunzipSync, gzipSync } from 'node:zlib';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { tarGzip, readTarGzip, indexedBundle, readBundle, writeAssets, verifyAssets, sourceIdentity } from '../../tools/v2/assets.mjs';

const files = [{ name: 'z/data.bin', bytes: Buffer.from([0, 255]) }, { name: 'a/run', bytes: Buffer.from('hello'), executable: true }];
function repairChecksum(bytes) {
  bytes.fill(32, 148, 156);
  const sum = bytes.subarray(0, 512).reduce((a, b) => a + b, 0);
  bytes.write(sum.toString(8).padStart(6, '0') + '\0 ', 148, 8, 'ascii');
}

test('deterministic archives round-trip regular files and executable mode', () => {
  const archive = tarGzip(files);
  assert.deepEqual(archive, tarGzip([...files].reverse()));
  assert.deepEqual(readTarGzip(archive), [{ ...files[1] }, { ...files[0], executable: false }]);
});

test('archive admission rejects unsafe paths, links, bad framing and padding', () => {
  const valid = gunzipSync(tarGzip([files[1]]));
  for (const mutate of [
    b => { b.fill(0, 0, 100); b.write('../escape', 0); },
    b => { b[156] = 50; b.write('/outside', 157); },
    b => { b[156] = 49; },
    b => { b[345] = 97; },
    b => { b.write('0000777\0', 100, 8, 'ascii'); },
    b => { b.write('77777777777\0', 124, 12, 'ascii'); },
    b => { b[517] = 1; },
  ]) {
    const bytes = Buffer.from(valid); mutate(bytes); repairChecksum(bytes);
    assert.throws(() => readTarGzip(gzipSync(bytes)));
  }
  const broken = Buffer.from(valid); broken[0] ^= 1;
  assert.throws(() => readTarGzip(gzipSync(broken)), /checksum/);
  assert.throws(() => readTarGzip(gzipSync(valid.subarray(0, valid.length - 512))), /terminator/);
  assert.throws(() => readTarGzip(gzipSync(Buffer.concat([valid, Buffer.from([1])]))), /terminator/);
  assert.throws(() => readTarGzip(gzipSync(Buffer.concat([valid.subarray(0, 1024), valid]))), /entry/);
});

test('container producers reject duplicate and escaping names', () => {
  for (const name of ['../x', '/x', 'a/../x', 'a//b', 'a\\b', './x']) {
    assert.throws(() => tarGzip([{ name, bytes: Buffer.alloc(0) }]));
    assert.throws(() => indexedBundle([{ name, bytes: Buffer.alloc(0) }]));
  }
  assert.throws(() => tarGzip([files[0], files[0]]));
  assert.throws(() => indexedBundle([files[0], files[0]]));
});

test('indexed data requires exact offsets, names, lengths and byte digests', () => {
  const bundle = indexedBundle(files);
  assert.deepEqual([...readBundle(bundle, bundle.bytes).keys()], ['a/run', 'z/data.bin']);
  for (const change of [
    b => { b.files[0].offset = 1; }, b => { b.files[1].name = b.files[0].name; },
    b => { b.files[0].length = Number.MAX_SAFE_INTEGER; }, b => { b.files[0].length = -1; },
    b => { b.files[0].sha256 = '0'.repeat(64); }, b => { b.files[0].name = '../x'; },
  ]) {
    const bad = structuredClone(bundle); change(bad);
    assert.throws(() => readBundle(bad, bundle.bytes));
  }
  assert.throws(() => readBundle(bundle, Buffer.concat([bundle.bytes, Buffer.from([0])])));
});

test('outer asset admission rejects inventory or content changes before consumers run', async () => {
  const cache = resolve(import.meta.dirname, '../../.cache/v2/assets-tests');
  await mkdir(cache, { recursive: true });
  const directory = await mkdtemp(join(cache, 'case-'));
  try {
    const entries = [{ name: 'first.bin', bytes: Buffer.from([1, 2, 3]) }];
    await writeAssets(directory, entries);
    assert.deepEqual((await verifyAssets(directory, ['first.bin'])).get('first.bin'), entries[0].bytes);
    await assert.rejects(verifyAssets(directory, ['first.bin', 'absent.bin']), /inventory/);
    await writeFile(join(directory, 'first.bin'), Buffer.from([1, 2, 4]));
    await assert.rejects(verifyAssets(directory, ['first.bin']), /digest/);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test('source identity belongs to the selected repository and immutable commit', async () => {
  const cache = resolve(import.meta.dirname, '../../.cache/v2/assets-tests');
  await mkdir(cache, { recursive: true });
  const directory = await mkdtemp(join(cache, 'source-'));
  const git = (...args) => execFileSync('git', ['-c', 'user.name=Source test', '-c', 'user.email=source@example.invalid', '-c', 'core.hooksPath=/dev/null', ...args], { cwd: directory }).toString().trim();
  try {
    git('init', '--quiet');
    await mkdir(join(directory, 'src'));
    await writeFile(join(directory, 'src/example.txt'), 'old contents');
    git('add', 'src'); git('commit', '--quiet', '--no-gpg-sign', '-m', 'old');
    const old = git('rev-parse', 'HEAD');
    await writeFile(join(directory, 'src/example.txt'), 'current contents');
    git('add', 'src'); git('commit', '--quiet', '--no-gpg-sign', '-m', 'current');
    const actual = await sourceIdentity(directory);
    git('replace', actual.git.head, old);
    assert.deepEqual(await sourceIdentity(directory), actual);
    const saved = process.env.GIT_DIR;
    try {
      process.env.GIT_DIR = join(directory, 'absent.git');
      assert.deepEqual(await sourceIdentity(directory), actual);
      await assert.rejects(sourceIdentity(join(directory, 'src')), /repository root/);
    } finally { if (saved === undefined) delete process.env.GIT_DIR; else process.env.GIT_DIR = saved; }
  } finally { await rm(directory, { recursive: true, force: true }); }
});
