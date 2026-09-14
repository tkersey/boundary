import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { command, parseArguments, preflight, runMeasurements } from './cold-guard.mjs';

function fixture(t) {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'cold guard test '));
  t.after(() => fs.rmSync(cwd, { recursive: true, force: true }));
  const args = [];
  for (const kind of ['boundary', 'world']) for (const side of ['baseline', 'candidate']) {
    const relative = `${kind} ${side}`, root = path.join(cwd, relative);
    fs.mkdirSync(root);
    command(root, ['init', '--quiet'], 'git');
    command(root, ['remote', 'add', 'origin', `https://github.com/tkersey/${kind}.git`], 'git');
    fs.writeFileSync(path.join(root, 'build.zig'), '// test only\n');
    command(root, ['add', 'build.zig'], 'git');
    command(root, ['-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'fixture'], 'git');
    args.push(`--${kind}-${side}`, relative);
  }
  args.push('--output', 'new results');
  return { cwd, args, options: parseArguments(args, cwd) };
}

test('explicit arbitrary roots, relative inputs and spaces survive preflight', t => {
  const { cwd, options } = fixture(t);
  const result = preflight(options);
  assert.equal(result.output, path.join(fs.realpathSync(cwd), 'new results'));
  assert.equal(result.sources.boundary[0].root, fs.realpathSync(options['boundary-baseline']));
  assert.equal(fs.existsSync(result.output), false);
});

test('required, unknown, duplicate and missing-value arguments', () => {
  assert.throws(() => parseArguments([]), /Missing required --boundary-baseline/);
  assert.throws(() => parseArguments(['old-positional-output']), /Unknown option/);
  assert.throws(() => parseArguments(['--output']), /Missing path/);
  assert.throws(() => parseArguments(['--output', 'x', '--output', 'y']), /Duplicate option/);
});

test('preflight rejects missing inputs, wrong repositories, dirty trees and existing outputs', t => {
  const { options } = fixture(t);
  assert.throws(() => preflight({ ...options, 'boundary-baseline': `${options['boundary-baseline']}/missing` }), /Missing checkout directory --boundary-baseline/);
  assert.throws(() => preflight({ ...options, 'boundary-baseline': options['world-baseline'] }), /Wrong repository origin/);
  const dirty = path.join(options['boundary-candidate'], 'untracked');
  fs.writeFileSync(dirty, 'dirty');
  assert.throws(() => preflight(options), /Dirty measured checkout/);
  fs.rmSync(dirty);
  fs.appendFileSync(path.join(options['boundary-candidate'], 'build.zig'), '// changed\n');
  assert.throws(() => preflight(options), /Dirty measured checkout/);
  command(options['boundary-candidate'], ['checkout', '--', 'build.zig'], 'git');
  fs.mkdirSync(options.output);
  fs.writeFileSync(path.join(options.output, 'keep'), 'original');
  assert.throws(() => preflight(options), /Output destination already exists/);
  assert.equal(fs.readFileSync(path.join(options.output, 'keep'), 'utf8'), 'original');
});

test('results cannot enter a measured tree through direct or symlink paths', t => {
  const { cwd, options } = fixture(t);
  assert.throws(() => preflight({ ...options, output: path.join(options['boundary-baseline'], 'results') }), /outside measured checkout/);
  const alias = path.join(cwd, 'alias');
  fs.symlinkSync(options['world-candidate'], alias, 'dir');
  assert.throws(() => preflight({ ...options, output: path.join(alias, 'results') }), /outside measured checkout/);
  fs.symlinkSync(path.join(cwd, 'missing'), options.output);
  assert.throws(() => preflight(options), /already exists/);
});

test('missing tools fail before output creation', t => {
  const { cwd, options } = fixture(t);
  const original = process.env.PATH;
  const bin = path.join(cwd, 'bin'); fs.mkdirSync(bin);
  const git = command(cwd, ['-c', 'command -v git'], '/bin/sh').stdout.toString().trim();
  fs.symlinkSync(git, path.join(bin, 'git'));
  try {
    process.env.PATH = bin;
    assert.throws(() => preflight(options), /Required executable not found on PATH: zig/);
    process.env.PATH = '';
    assert.throws(() => preflight(options), /Required executable not found on PATH: git/);
    assert.equal(fs.existsSync(options.output), false);
  } finally { process.env.PATH = original; }
});

test('launch, signal and nonzero diagnostics identify executable, args, cwd and cause', t => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'cold command '));
  t.after(() => fs.rmSync(cwd, { recursive: true, force: true }));
  for (const [root, executable, args, reason] of [
    [cwd, path.join(cwd, 'missing executable'), ['a b'], /ENOENT/],
    [path.join(cwd, 'missing cwd'), process.execPath, ['--version'], /ENOENT/],
    [cwd, process.execPath, ['-e', 'process.kill(process.pid, "SIGTERM")'], /signal SIGTERM/],
    [cwd, process.execPath, ['-e', 'console.error("relevant stderr"); process.exit(7)'], /exit status 7[\s\S]*relevant stderr/],
  ]) assert.throws(() => command(root, args, executable), error => {
    assert.match(error.message, reason);
    assert.ok(error.message.includes(JSON.stringify(executable)));
    assert.ok(error.message.includes(JSON.stringify(args)));
    assert.ok(error.message.includes(`cwd: ${root}`));
    return true;
  });
});

test('a failed measurement retains successful rows without a success result', t => {
  const { options } = fixture(t);
  const config = preflight(options);
  let calls = 0;
  // Simulated builds test failure bookkeeping only; this is not performance evidence.
  const run = (cwd, args, executable) => {
    if (++calls === 2) return command(cwd, args, '/missing-zig');
    const local = args[args.indexOf('--cache-dir') + 1];
    fs.mkdirSync(path.join(local, 'o', 'test'), { recursive: true });
    fs.writeFileSync(path.join(local, 'o', 'test', 'one-effect'), 'stub');
    return { ms: 1, stdout: Buffer.from('BPI2 test'), stderr: Buffer.alloc(0) };
  };
  assert.throws(() => runMeasurements(config, run, () => {}), /Incomplete run/);
  const partial = JSON.parse(fs.readFileSync(path.join(config.output, 'partial.json')));
  assert.equal(partial.status, 'failed');
  assert.equal(partial.rows.length, 1);
  assert.equal(partial.failure.executable, '/missing-zig');
  assert.equal(fs.existsSync(path.join(config.output, 'cold-guard.json')), false);
});

test('CLI executes through a symlink instead of silently skipping main', t => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'cold CLI '));
  t.after(() => fs.rmSync(cwd, { recursive: true, force: true }));
  const alias = path.join(cwd, 'guard alias.mjs');
  fs.symlinkSync(new URL('./cold-guard.mjs', import.meta.url), alias);
  for (const flags of [[], ['--preserve-symlinks-main'], ['--preserve-symlinks', '--preserve-symlinks-main']]) {
    assert.match(command(cwd, [...flags, alias, '--help'], process.execPath).stdout.toString(), /Usage: node/);
    assert.throws(() => command(cwd, [...flags, alias], process.execPath), /Missing required --boundary-baseline/);
  }
  assert.throws(() => command(cwd, [alias], process.execPath), /Missing required --boundary-baseline/);
});

test('importing the guard does not execute the CLI, including preserved aliases', t => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'cold import '));
  t.after(() => fs.rmSync(cwd, { recursive: true, force: true }));
  const alias = path.join(cwd, 'guard.mjs');
  fs.symlinkSync(new URL('./cold-guard.mjs', import.meta.url), alias);
  fs.writeFileSync(path.join(cwd, 'caller.mjs'), 'import "./guard.mjs"; console.log("imported");');
  for (const flags of [[], ['--preserve-symlinks', '--preserve-symlinks-main']]) {
    assert.equal(command(cwd, [...flags, 'caller.mjs'], process.execPath).stdout.toString(), 'imported\n');
  }
});

test('PATH tool symlinks retain their dispatch name', t => {
  const { cwd, options } = fixture(t);
  const original = process.env.PATH;
  const selected = preflight(options).tools;
  const bin = path.join(cwd, 'tool shims'); fs.mkdirSync(bin);
  const dispatcher = path.join(bin, 'dispatch.cjs');
  fs.writeFileSync(dispatcher, `#!${process.execPath}\nconst {spawnSync}=require('node:child_process');const {basename}=require('node:path');const selected=${JSON.stringify(selected)};const executable=selected[basename(process.argv[1])];if(!executable)process.exit(93);const r=spawnSync(executable,process.argv.slice(2),{stdio:'inherit'});process.exit(r.status??1);\n`, { mode: 0o755 });
  for (const name of ['git', 'zig']) fs.symlinkSync(dispatcher, path.join(bin, name));
  try {
    process.env.PATH = `${bin}${path.delimiter}${original}`;
    const result = preflight(options);
    assert.equal(result.tools.zig, path.join(bin, 'zig'));
    assert.equal(result.tools.git, path.join(bin, 'git'));
    assert.equal(result.versions.zig, '0.16.0');
  } finally { process.env.PATH = original; }
});
