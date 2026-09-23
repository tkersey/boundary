// Build the retained public client against a clean package copy outside the tree.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cpSync, mkdtempSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const temporary = mkdtempSync(join(tmpdir(), 'boundary-public-authoring-'));
try {
  const packageRoot = join(temporary, 'boundary');
  const clientRoot = join(temporary, 'client');
  mkdirSync(packageRoot);
  mkdirSync(clientRoot);
  for (const name of ['LICENSE', 'README.md', 'build.zig', 'build.zig.zon',
    'repo_zig_paths.txt', 'src', 'docs', 'examples', 'test', 'tools']) {
    cpSync(join(root, name), join(packageRoot, name), { recursive: true });
  }
  cpSync(join(root, 'test/public_authoring_client'), clientRoot,
    { recursive: true, force: true });
  const image = execFileSync('zig', ['build', 'test', 'emit',
    '-Doptimize=ReleaseSafe'], { cwd: clientRoot, maxBuffer: 8 << 20,
    timeout: 180000 });
  assert.equal(image.subarray(0, 8).toString(), 'ABL_BPI3');
  console.log(JSON.stringify({ check: 'public package authoring client',
    imageBytes: image.length, tests: 'passed' }));
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
