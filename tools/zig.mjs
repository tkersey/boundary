// One compiler selection for a qualification command and all of its children.
import { accessSync, constants, lstatSync, readdirSync, readFileSync, realpathSync } from 'node:fs';
import { delimiter, isAbsolute, join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
function executableOnPath(path) {
  for (const directory of path.split(delimiter)) {
    const candidate = resolve(directory || '.', process.platform === 'win32' ? 'zig.exe' : 'zig');
    try { accessSync(candidate, constants.X_OK); return realpathSync(candidate); }
    catch (error) { if (!['ENOENT', 'ENOTDIR', 'EACCES'].includes(error.code)) throw error; }
  }
  throw new Error('ZigUnavailable: select --zig-exe ABSOLUTE_PATH');
}
function fileIdentity(path) {
  const stat = lstatSync(path);
  if (!stat.isFile() || stat.size > 512 * 1024 * 1024) throw new Error('ZigDistributionInvalid');
  return { bytes: stat.size, mode: stat.mode & 0o777, sha256: hash(readFileSync(path)) };
}
function identity(executable, library) {
  const files = [];
  let bytes = 0;
  function visit(directory, relative = '', depth = 0) {
    if (depth > 32) throw new Error('ZigDistributionTooDeep');
    for (const name of readdirSync(directory).sort()) {
      if (files.length >= 100000) throw new Error('ZigDistributionTooLarge');
      const path = join(directory, name), child = relative ? `${relative}/${name}` : name;
      const stat = lstatSync(path);
      if (stat.isDirectory()) {
        files.push({ path: child, directory: true, mode: stat.mode & 0o777 });
        visit(path, child, depth + 1);
      } else {
        const item = fileIdentity(path);
        bytes += item.bytes;
        if (bytes > 1024 * 1024 * 1024) throw new Error('ZigDistributionTooLarge');
        files.push({ path: child, ...item });
      }
    }
  }
  visit(library);
  return { version: '0.17.0', executable, executableIdentity: fileIdentity(executable), library,
    libraryInventorySha256: hash(JSON.stringify(files)), libraryEntries: files.length, libraryBytes: bytes };
}

export function selectZig(argv, { inherited = process.env.BOUNDARY_ZIG_EXE } = {}) {
  const args = [], selections = new Map();
  for (let i = 0; i < argv.length; i++) {
    const name = argv[i];
    if (!['--zig-exe', '--zig-lib'].includes(name)) { args.push(name); continue; }
    const value = argv[++i];
    if (selections.has(name) || !value || !isAbsolute(value))
      throw new Error(`${name} requires one absolute path`);
    selections.set(name, realpathSync(value));
  }
  if (inherited && !isAbsolute(inherited)) throw new Error('Inherited Zig path must be absolute');
  const outer = inherited && realpathSync(inherited), explicit = selections.get('--zig-exe');
  if (outer && explicit && outer !== explicit) throw new Error('Conflicting Zig selections');
  const executable = outer ?? explicit ?? executableOnPath(process.env.PATH ?? '');
  const env = { ...process.env, BOUNDARY_ZIG_EXE: executable };
  if (selections.has('--zig-lib')) env.ZIG_LIB_DIR = selections.get('--zig-lib');
  const options = { encoding: 'utf8', maxBuffer: 64 * 1024, timeout: 30000, env };
  if (execFileSync(executable, ['version'], options).trim() !== '0.17.0')
    throw new Error('Zig 0.17.0 is required');
  // The pinned release emits ZON. Read only its single, quoted lib_dir field;
  // unsupported string escapes or duplicate fields reject instead of guessing.
  const description = execFileSync(executable, ['env'], options);
  const fields = [...description.matchAll(/^\s*\.lib_dir = ("(?:[^"\\\r\n]|\\.)*"),$/gm)];
  if (fields.length !== 1) throw new Error('Invalid Zig library description');
  const library = realpathSync(resolve(JSON.parse(fields[0][1])));
  env.ZIG_LIB_DIR = library;
  const before = identity(executable, library);
  return { args, executable, env, identity: before,
    assertUnchanged() {
      if (JSON.stringify(identity(executable, library)) !== JSON.stringify(before))
        throw new Error('Zig distribution changed during qualification');
    } };
}
