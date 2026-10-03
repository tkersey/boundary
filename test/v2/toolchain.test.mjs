import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, writeFile, chmod, rm, readFile } from 'node:fs/promises';
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
  const f = await fixture(t), dev = await fixture(t, '0.17.0-dev.1');
  assert.throws(() => selectZig(['--zig-exe', './zig']), /absolute/);
  assert.throws(() => selectZig(['--zig-exe', f.executable, '--zig-exe', f.executable]), /one absolute/);
  assert.throws(() => selectZig(['--zig-exe', f.executable], { inherited: selected.executable }), /Conflicting/);
  assert.throws(() => selectZig(['--zig-exe', dev.executable], { inherited: null }), /0.17.0 is required/);
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
