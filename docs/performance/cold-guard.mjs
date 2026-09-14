import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const names = ['boundary-baseline', 'boundary-candidate', 'world-baseline', 'world-candidate', 'output'];
export const usage = `Usage: node docs/performance/cold-guard.mjs ${names.map(name => `--${name} PATH`).join(' ')}
Paths are resolved against the invocation directory. All four checkouts must be
clean repository roots with a tkersey/boundary or tkersey/world origin, respectively.
The output must not exist; its parent must exist outside all measured checkouts.
Requires git and Zig 0.16.0 on PATH. See docs/api-preserving-performance.md.`;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const writeJson = (file, value) => fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n');
const inside = (parent, child) => { const relative = path.relative(parent, child); return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative)); };

export function parseArguments(argv, cwd = process.cwd()) {
  const options = {};
  for (let i = 0; i < argv.length; i += 2) {
    const name = argv[i].slice(2);
    if (argv[i] !== `--${name}` || !names.includes(name)) throw new Error(`Unknown option: ${argv[i]}\n${usage}`);
    if (Object.hasOwn(options, name)) throw new Error(`Duplicate option: --${name}`);
    if (!argv[i + 1] || argv[i + 1].startsWith('--')) throw new Error(`Missing path for --${name}`);
    options[name] = path.resolve(cwd, argv[i + 1]);
  }
  for (const name of names) if (!options[name]) throw new Error(`Missing required --${name}\n${usage}`);
  return options;
}

// Time exactly the synchronous process launch/wait, as in the original harness.
export function command(cwd, args, executable = 'zig', runner = spawnSync) {
  const start = performance.now();
  const result = runner(executable, args, { cwd, maxBuffer: 64 << 20 });
  const ms = performance.now() - start;
  const stderr = result.stderr?.toString() ?? '';
  const reason = result.error ? `launch error: ${result.error.code ?? ''} ${result.error.message}`
    : result.signal ? `terminated by signal ${result.signal}`
      : result.status !== 0 ? `exit status ${result.status}` : null;
  if (reason) {
    const error = new Error(`${JSON.stringify(executable)} ${JSON.stringify(args)}\ncwd: ${cwd}\n${reason}${stderr ? `\nstderr:\n${stderr}` : ''}`);
    error.subprocess = { executable, args, cwd, milliseconds: ms, status: result.status, signal: result.signal, reason, stderr };
    throw error;
  }
  return { ms, stdout: result.stdout ?? Buffer.alloc(0), stderr: result.stderr ?? Buffer.alloc(0) };
}

function executableOnPath(name) {
  for (const entry of (process.env.PATH ?? '').split(path.delimiter)) {
    const candidate = path.resolve(entry || '.', name);
    try { if (fs.statSync(candidate).isFile()) { fs.accessSync(candidate, fs.constants.X_OK); return fs.realpathSync(candidate); } } catch {}
  }
  throw new Error(`Required executable not found on PATH: ${name}`);
}

function sourceIdentity(root, kind, git, run) {
  const query = args => run(root, args, git).stdout.toString().trim();
  assert.equal(fs.realpathSync(query(['rev-parse', '--show-toplevel'])), root, `Expected repository root: ${root}`);
  const origin = query(['remote', 'get-url', 'origin']);
  assert.ok(new RegExp(`^(?:https://github\\.com/|git@github\\.com:|ssh://git@github\\.com/)tkersey/${kind}(?:\\.git)?/?$`).test(origin), `Wrong repository origin at ${root}: ${origin}; expected tkersey/${kind}`);
  assert.equal(query(['status', '--porcelain', '--untracked-files=all']), '', `Dirty measured checkout: ${root}`);
  assert.ok(fs.statSync(path.join(root, 'build.zig')).isFile(), `Missing build.zig: ${root}`);
  return { root, origin, commit: query(['rev-parse', 'HEAD']), tree: query(['rev-parse', 'HEAD^{tree}']), dirty: false };
}

export function preflight(options, run = command) {
  const tools = Object.fromEntries(['git', 'zig'].map(name => [name, executableOnPath(name)]));
  const versions = { git: run(process.cwd(), ['--version'], tools.git).stdout.toString().trim(), zig: run(process.cwd(), ['version'], tools.zig).stdout.toString().trim(), node: process.version };
  assert.equal(versions.zig, '0.16.0', `Expected Zig 0.16.0, found ${versions.zig}`);
  const sources = {};
  for (const kind of ['boundary', 'world']) sources[kind] = ['baseline', 'candidate'].map(side => {
    const input = options[`${kind}-${side}`];
    assert.ok(fs.existsSync(input) && fs.statSync(input).isDirectory(), `Missing checkout directory --${kind}-${side}: ${input}`);
    return sourceIdentity(fs.realpathSync(input), kind, tools.git, run);
  });
  const requested = options.output;
  // lstat also rejects dangling symlinks, which must not be reused as outputs.
  try { fs.lstatSync(requested); throw new Error(`Output destination already exists: ${requested}`); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const output = path.join(fs.realpathSync(path.dirname(requested)), path.basename(requested));
  for (const source of Object.values(sources).flat()) assert.ok(!inside(source.root, output), `Output must be outside measured checkout: ${source.root}`);
  return { output, sources, tools, versions, toolSha256: Object.fromEntries(Object.entries(tools).map(([name, executable]) => [name, hash(fs.readFileSync(executable))])) };
}

export function runMeasurements(config, run = command, log = console.log) {
  const { output, sources, tools, versions } = config;
  fs.mkdirSync(output); // Exclusive creation after every preflight check; never reuse caches.
  const roots = Object.fromEntries(Object.entries(sources).map(([kind, pair]) => [kind, pair.map(source => source.root)]));
  const state = {
    status: 'running',
    method: 'five paired AB/BA builds per workload, fresh local/global object caches; already-built emitter measured separately with five warmups and 21 paired process launches',
    limits: 'Object caches are cold; OS filesystem caches are not flushed. Build-driver/analysis/codegen/link times are included together, not independently attributed. Emitter timing includes process startup.',
    environment: { date: new Date().toISOString(), cpu: os.cpus()[0].model, platform: os.platform(), release: os.release(), arch: os.arch(), versions, tools, toolSha256: config.toolSha256, overrides: Object.fromEntries(['ZIG_LIB_DIR', 'ZIG_GLOBAL_CACHE_DIR', 'CC', 'CFLAGS', 'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET'].filter(name => process.env[name] !== undefined).map(name => [name, process.env[name]])) },
    harnessSha256: hash(fs.readFileSync(fileURLToPath(import.meta.url))),
    identities: Object.fromEntries(Object.entries(sources).map(([kind, pair]) => [kind, pair.map(source => source.commit)])),
    sources, output, rows: [], emitterRows: [],
  };
  const save = () => writeJson(path.join(output, 'partial.json'), state);
  const emitterPaths = [];
  save();
  try {
    for (const kind of ['boundary', 'world']) for (let sample = 0; sample < 5; sample++) for (const side of sample % 2 ? [1, 0] : [0, 1]) {
      const root = roots[kind][side];
      const scratch = path.join(output, `${kind}-${sample}-${side}`);
      fs.mkdirSync(scratch);
      const local = path.join(scratch, 'local'), global = path.join(scratch, 'global'), prefix = path.join(scratch, 'out');
      const args = ['build', kind === 'boundary' ? 'emit-one-effect' : 'build-v2-kernel', '-Doptimize=ReleaseSafe', '--cache-dir', local, '--global-cache-dir', global, '--prefix', prefix];
      if (kind === 'world') args.push(`-Dboundary-v2-source=${roots.boundary[side]}`);
      const result = run(root, args, tools.zig);
      fs.writeFileSync(path.join(scratch, 'stderr.txt'), result.stderr);
      let artifact;
      if (kind === 'boundary') {
        artifact = result.stdout;
        const directory = path.join(local, 'o');
        const candidates = fs.readdirSync(directory).map(name => path.join(directory, name, 'one-effect')).filter(name => fs.existsSync(name));
        assert.equal(candidates.length, 1, `Expected one built emitter in ${directory}`);
        if (sample === 0) emitterPaths[side] = candidates[0];
      } else artifact = fs.readFileSync(path.join(prefix, 'world-process-kernel-v2.wasm'));
      const row = { kind, sample, order: sample % 2 ? 'BA' : 'AB', side, root, args, milliseconds: result.ms, artifactBytes: artifact.length, artifactSha256: hash(artifact) };
      state.rows.push(row); save(); log(JSON.stringify(row));
    }
    state.emitters = emitterPaths.map(executable => ({ executable, sha256: hash(fs.readFileSync(executable)) }));
    for (let warmup = 0; warmup < 5; warmup++) for (const executable of emitterPaths) run(output, [], executable);
    for (let sample = 0; sample < 21; sample++) for (const side of sample % 2 ? [1, 0] : [0, 1]) {
      const result = run(output, [], emitterPaths[side]);
      state.emitterRows.push({ sample, side, milliseconds: result.ms, imageSha256: hash(result.stdout) }); save();
    }
    assert.equal(new Set([...state.rows.filter(row => row.kind === 'boundary').map(row => row.artifactSha256), ...state.emitterRows.map(row => row.imageSha256)]).size, 1, 'Build and emitter BPI2 outputs must agree');
    for (const side of [0, 1]) assert.equal(new Set(state.rows.filter(row => row.kind === 'world' && row.side === side).map(row => row.artifactSha256)).size, 1, 'Kernel must be reproducible per side');
    for (const kind of ['boundary', 'world']) for (const source of sources[kind]) assert.deepEqual(sourceIdentity(source.root, kind, tools.git, run), source, `Measured source changed: ${source.root}`);
    state.status = 'completed'; save();
    writeJson(path.join(output, 'cold-guard.json'), state);
    return state;
  } catch (error) {
    state.status = 'failed'; state.failure = error.subprocess ?? { message: error.message }; save();
    throw new Error(`${error.message}\nIncomplete run; available results retained in ${output}/partial.json`, { cause: error });
  }
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length === 3 && process.argv[2] === '--help') console.log(usage);
    else runMeasurements(preflight(parseArguments(process.argv.slice(2))));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
