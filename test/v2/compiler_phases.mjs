// Exclusive compiler/codec phases through the public compiler observer.
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import os from 'node:os';
import { sourceIdentity, sha256, json } from '../../tools/v2/assets.mjs';

const [outputArgument] = process.argv.slice(2);
assert.ok(outputArgument && process.argv.length === 3, 'expected isolated output directory');
const root = resolve(import.meta.dirname, '../..'), output = resolve(outputArgument);
await mkdir(output, { recursive: true });
async function compilerInputs() {
  const identity = await sourceIdentity(root);
  const files = identity.files.filter(({ name }) => name.startsWith('src/v2/') || ['build.zig', 'build.zig.zon', 'test/v2/compiler_phases.zig', 'test/v2/compiler_phases.mjs', 'tools/v2/assets.mjs'].includes(name));
  return { git: identity.git, fileScope: 'compiler, build driver and phase measurement code', files, filesSha256: sha256(json(files)) };
}
const source = await compilerInputs();
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
function command(file, args) {
  const run = spawnSync(file, args, { cwd: root, maxBuffer: 16 << 20, timeout: 180000 });
  assert.equal(run.status, 0, run.stderr?.toString());
  return run.stdout;
}
const names = ['one-shot', 'multi', 'local-cells', 'resource', 'retained-search', 'install-1', 'install-8', 'install-64'];
const executables = [];
for (let kind = 0; kind < names.length; kind++) {
  const prefix = join(output, `kind-${kind}`);
  command('zig', ['build', 'build-v2-compiler-phases', '-Doptimize=ReleaseSafe', `-Dcompiler-phase-kind=${kind}`,
    '--cache-dir', join(output, 'local'), '--global-cache-dir', join(output, 'global'), '--prefix', prefix]);
  executables.push(join(prefix, 'bin/compiler-phases'));
}
const workloads = [];
for (let kind = 0; kind < names.length; kind++) {
  const samples = JSON.parse(command(executables[kind], []));
  const first = samples.measurements[0];
  const phases = Object.fromEntries(Object.keys(first.phases).map(name => [name, median(samples.measurements.map(row => row.phases[name]))]));
  const row = { name: names[kind], executableSha256: sha256(await readFile(executables[kind])), phaseMediansNs: phases, ...samples };
  workloads.push(row);
  console.log(JSON.stringify({ name: row.name, imageBytes: first.image_bytes, phaseMediansNs: phases }));
}
assert.equal((await compilerInputs()).filesSha256, source.filesSha256, 'compiler inputs changed');
await writeFile(join(output, 'compiler-phases.json'), JSON.stringify({ format: 'boundary-v2-compiler-phases/v1',
  environment: { date: new Date().toISOString(), cpu: os.cpus()[0].model, platform: os.platform(), release: os.release(), node: process.version, zig: command('zig', ['version']).toString().trim() },
  source, optimize: 'ReleaseSafe', method: 'all profilers built before timing; five warmups and 21 serial samples; 16 MiB fixed scratch; exclusive observed compiler phases; pure codecs use admitted initial logical State; no evaluator', workloads }, null, 2) + '\n');
