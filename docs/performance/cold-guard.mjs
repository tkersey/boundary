import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { createHash } from 'node:crypto';

const outputArgument = process.argv[2];
assert.ok(outputArgument, 'expected an unused output directory');
const output = path.resolve(outputArgument);
fs.mkdirSync(output); // Never silently reuse a cold cache.
const roots = {
  boundary: ['/Users/tk/.codex/worktrees/perf-reference/boundary', '/Users/tk/.codex/worktrees/e38a/boundary'],
  world: ['/Users/tk/.codex/worktrees/perf-reference/world', '/Users/tk/.codex/worktrees/e38a/world'],
};
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
function command(cwd, args, executable = 'zig') {
  const start = performance.now();
  const result = spawnSync(executable, args, { cwd, maxBuffer: 64 << 20 });
  assert.equal(result.status, 0, result.stderr?.toString());
  return { ms: performance.now() - start, stdout: result.stdout, stderr: result.stderr };
}
const identities = Object.fromEntries(Object.entries(roots).map(([name, pair]) => [name, pair.map(root => {
  assert.equal(command(root, ['status', '--porcelain'], 'git').stdout.toString(), '');
  return command(root, ['rev-parse', 'HEAD'], 'git').stdout.toString().trim();
})]));
const rows = [];
const emitterPaths = [];
for (const kind of ['boundary', 'world']) {
  for (let sample = 0; sample < 5; sample++) {
    for (const side of sample % 2 ? [1, 0] : [0, 1]) {
      const root = roots[kind][side];
      const scratch = path.join(output, `${kind}-${sample}-${side}`);
      fs.mkdirSync(scratch);
      const local = path.join(scratch, 'local'), global = path.join(scratch, 'global'), prefix = path.join(scratch, 'out');
      const args = ['build', kind === 'boundary' ? 'emit-one-effect' : 'build-v2-kernel', '-Doptimize=ReleaseSafe',
        '--cache-dir', local, '--global-cache-dir', global, '--prefix', prefix];
      if (kind === 'world') args.push(`-Dboundary-v2-source=${roots.boundary[side]}`);
      const result = command(root, args);
      fs.writeFileSync(path.join(scratch, 'stderr.txt'), result.stderr);
      let artifact;
      if (kind === 'boundary') {
        artifact = result.stdout;
        const directory = path.join(local, 'o');
        const candidates = fs.readdirSync(directory).map(name => path.join(directory, name, 'one-effect')).filter(name => fs.existsSync(name));
        assert.equal(candidates.length, 1);
        if (sample === 0) emitterPaths[side] = candidates[0];
      } else artifact = fs.readFileSync(path.join(prefix, 'world-process-kernel-v2.wasm'));
      const row = { kind, sample, order: sample % 2 ? 'BA' : 'AB', side, root, args, milliseconds: result.ms,
        artifactBytes: artifact.length, artifactSha256: hash(artifact) };
      rows.push(row);
      fs.writeFileSync(path.join(output, 'partial.json'), JSON.stringify({ identities, rows }, null, 2));
      console.log(JSON.stringify(row));
    }
  }
}
const emitterRows = [];
for (let warmup = 0; warmup < 5; warmup++) for (const executable of emitterPaths) command(output, [], executable);
for (let sample = 0; sample < 21; sample++) for (const side of sample % 2 ? [1, 0] : [0, 1]) {
  const result = command(output, [], emitterPaths[side]);
  emitterRows.push({ sample, side, milliseconds: result.ms, imageSha256: hash(result.stdout) });
}
assert.equal(new Set(rows.filter(row => row.kind === 'boundary').map(row => row.artifactSha256)).size, 1);
assert.equal(new Set(emitterRows.map(row => row.imageSha256)).size, 1);
fs.writeFileSync(path.join(output, 'cold-guard.json'), JSON.stringify({
  method: 'five paired AB/BA builds per workload, fresh local/global object caches; already-built emitter measured separately with five warmups and 21 paired process launches',
  limits: 'Object caches are cold; OS filesystem caches are not flushed. Build-driver/analysis/codegen/link times are included together, not independently attributed. Emitter timing includes process startup.',
  environment: { date: new Date().toISOString(), cpu: os.cpus()[0].model, platform: os.platform(), release: os.release(), zig: command(output, ['version']).stdout.toString().trim() },
  harnessSha256: hash(fs.readFileSync(import.meta.filename)), identities, rows, emitterRows,
}, null, 2) + '\n');
