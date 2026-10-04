import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, writeFile, chmod, rm, readFile, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { selectZig } from '../../tools/zig.mjs';

const selected = selectZig(process.argv.slice(2));
const quote = text => `'${text.replaceAll("'", "'\\''")}'`;
async function fixture(t, version = '0.17.0') {
  const root = await mkdtemp(join(tmpdir(), 'zig selection '));
  t.after(() => rm(root, { recursive: true, force: true }));
  const library = join(root, 'lib'), executable = join(root, 'zig');
  await mkdir(library);
  await writeFile(join(library, 'std.zig'), '// fixture library\n');
  const description = `.{\n    .lib_dir = ${JSON.stringify(library)},\n}\n`;
  await writeFile(executable, `#!/bin/sh\ncase "$1" in\nversion) printf '%s\\n' ${quote(version)};;\nenv) printf '%s' ${quote(description)};;\n*) exit 79;;\nesac\n`);
  await chmod(executable, 0o755);
  return { root, library, executable };
}

test('explicit selection survives a poisoned PATH without invoking its zig', async t => {
  const f = await fixture(t);
  const compiler = selectZig(['--zig-exe', selected.executable], { inherited: undefined });
  const result = execFileSync(compiler.executable, ['version'], {
    encoding: 'utf8', env: { ...compiler.env, PATH: f.root }, timeout: 30000,
  });
  assert.equal(result.trim(), '0.17.0');
  compiler.assertUnchanged();
});

test('relative, duplicate, conflicting and development compiler selections reject', async t => {
  const f = await fixture(t), dev = await fixture(t, '0.17.0-dev.1'), old = await fixture(t, '0.16.0');
  assert.throws(() => selectZig(['--zig-exe', './zig']), /absolute/);
  assert.throws(() => selectZig(['--zig-exe', f.executable, '--zig-exe', f.executable]), /one absolute/);
  assert.throws(() => selectZig(['--zig-exe', f.executable], { inherited: selected.executable }), /Conflicting/);
  assert.throws(() => selectZig(['--zig-exe', dev.executable], { inherited: null }), /0.17.0 is required/);
  assert.throws(() => selectZig(['--zig-exe', old.executable], { inherited: null }), /0.17.0 is required/);
});

test('unchanged reported version cannot hide compiler or library replacement', async t => {
  for (const kind of ['compiler', 'library', 'entry']) {
    const f = await fixture(t);
    const compiler = selectZig(['--zig-exe', f.executable], { inherited: null });
    compiler.assertUnchanged();
    if (kind === 'compiler') await writeFile(f.executable, (await readFile(f.executable)) + '# changed\n');
    else await writeFile(join(f.library, kind === 'library' ? 'std.zig' : 'new.zig'), '// changed\n');
    assert.throws(() => compiler.assertUnchanged(), /distribution changed/);
  }
});

test('library description must identify exactly one bounded directory', async t => {
  const f = await fixture(t);
  const body = await readFile(f.executable, 'utf8');
  await writeFile(f.executable, body.replace('    .lib_dir = ', `    .lib_dir = ${JSON.stringify(f.library)},\n    .lib_dir = `));
  assert.throws(() => selectZig(['--zig-exe', f.executable], { inherited: null }), /Invalid Zig library/);
  await writeFile(f.executable, "#!/bin/sh\nif [ \"$1\" = version ]; then printf '0.17.0\\n'; else printf '%70000s' ''; fi\n");
  assert.throws(() => selectZig(['--zig-exe', f.executable], { inherited: null }), error => error.code === 'ENOBUFS');
});

process.on('beforeExit', () => selected.assertUnchanged());

test('standalone build-file selection survives a shared configuration cache', async t => {
  const { resolve } = await import('node:path');
  const root = resolve(import.meta.dirname, '../..');
  const cache = await mkdtemp(join(tmpdir(), 'boundary build selection '));
  t.after(() => rm(cache, { recursive: true, force: true }));
  for (const [file, present, absent] of [
    ['build_authoring_economy.zig', 'reference', 'allocation'],
    ['build_hyper_compiler.zig', 'allocation', 'reference'],
    ['build_authoring_economy.zig', 'reference', 'allocation'],
  ]) {
    const output = execFileSync(selected.executable, ['build', '--build-file', join(root, 'test', file),
      `-Dsource=${root}`, '--cache-dir', cache, '--list-steps'], {
      cwd: root, env: selected.env, encoding: 'utf8', timeout: 120000,
    });
    assert.match(output, new RegExp(`\\b${present}\\b`));
    assert.doesNotMatch(output, new RegExp(`\\b${absent}\\b`));
  }
});

test('Run preserves pass-through and long arguments without recompiling the executable', async t => {
  const root = await mkdtemp(join(tmpdir(), 'boundary args Ω '));
  t.after(() => rm(root, { recursive: true, force: true }));
  await writeFile(join(root, 'main.zig'), `const std = @import("std");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    var json: std.json.Stringify = .{ .writer = &output.interface };
    try json.beginArray();
    while (args.next()) |arg| try json.write(arg);
    try json.endArray();
    try output.interface.flush();
}
`);
  await writeFile(join(root, 'build.zig'), `const std = @import("std");
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{ .name = "argv-probe", .root_module = b.createModule(.{
        .root_source_file = b.path("main.zig"), .target = b.graph.host, .optimize = .safe,
    }) });
    const run = b.addRunArtifact(exe);
    if (b.option(bool, "long", "Exercise an actual long command line") orelse false)
        for (0..1000) |_| run.addArg("a repeated argument with spaces and Unicode Ω");
    run.addPassthruArgs();
    const step = b.step("args", "Preserve exact child arguments");
    step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    step.dependOn(&b.addInstallFileWithDir(run.captureStdOut(.{}), .prefix, "argv.json").step);
}
`);
  const prefix = join(root, 'output Ω'), cache = join(root, 'cache');
  let initial;
  for (const [long, args] of [
    [false, ['', 'space value', 'Ω', '-leading-dash', 'repeat', 'repeat']],
    [false, ['', 'changed value', 'Ω', '-leading-dash', 'repeat', 'repeat']],
    [true, ['', '--', 'tail Ω']],
  ]) {
    execFileSync(selected.executable, ['build', 'args', `-Dlong=${long}`,
      '--cache-dir', cache, '--prefix', prefix, '--summary', 'all', '--', ...args], {
      cwd: root, env: selected.env, encoding: 'utf8', timeout: 120000,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const expected = [...(long ? Array(1000).fill('a repeated argument with spaces and Unicode Ω') : []), ...args];
    assert.deepEqual(JSON.parse(await readFile(join(prefix, 'argv.json'), 'utf8')), expected);
    const binary = join(prefix, 'bin', 'argv-probe');
    const observed = { bytes: await readFile(binary), modified: (await stat(binary)).mtimeMs };
    if (initial) assert.deepEqual(observed, initial, 'runtime arguments must not rebuild the executable');
    else initial = observed;
  }
});
