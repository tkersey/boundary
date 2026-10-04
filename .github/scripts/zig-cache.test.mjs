import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { inspectCache } from './zig-cache.mjs';

test('cache admission retains useful objects and never erases oversized, empty, or aliased caches', t => {
  const root = mkdtempSync(join(tmpdir(), 'zig-cache-admission-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  assert.equal(inspectCache(root, 8).save, false);
  mkdirSync(join(root, 'o')); mkdirSync(join(root, 'h'));
  writeFileSync(join(root, 'h', 'manifest'), 'h');
  assert.equal(inspectCache(root, 8).save, false);
  writeFileSync(join(root, 'o', 'object'), 'object');
  assert.equal(inspectCache(root, 7).save, true);
  assert.equal(inspectCache(root, 6).save, false);
  assert.deepEqual({ ...inspectCache(root, 7).groups }, { h: 1, o: 6 });
  assert.equal(readFileSync(join(root, 'o', 'object'), 'utf8'), 'object');
  symlinkSync(join(root, 'o', 'object'), join(root, 'alias'));
  assert.equal(inspectCache(root, 100).save, false);
  assert.equal(readFileSync(join(root, 'o', 'object'), 'utf8'), 'object');
});
