// Copyright (c) 2026 Boundary contributors. MIT license.
// Module discovery/building is separate from Lean's declaration/axiom audit.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const project = fileURLToPath(new URL('.', import.meta.url));

function discover(directory, prefix = []) {
  const modules = [];
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.name === '.lake') continue;
    const path = join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`trust source symlink: ${path}`);
    if (entry.isDirectory()) modules.push(...discover(path, [...prefix, entry.name]));
    else if (entry.isFile() && entry.name.endsWith('.lean')) {
      const parts = [...prefix, entry.name.slice(0, -5)];
      assert(parts.every(part => /^[A-Za-z_][A-Za-z0-9_]*$/.test(part)), `unsupported module path: ${path}`);
      modules.push({ name: parts.join('.'), source: readFileSync(path, 'utf8') });
    }
  }
  return modules;
}

function lake(directory, args) {
  const result = spawnSync('lake', args, { cwd: directory, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  if (result.error) throw result.error;
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  if (result.status !== 0) throw new Error(`lake ${args.join(' ')} failed (${result.status ?? result.signal})\n${output}`);
  return output;
}

export function check(directory = project, { replay = true, mutation = false } = {}) {
  const modules = discover(directory);
  assert(modules.some(m => m.name === 'BoundaryV2') && modules.some(m => m.name === 'Trust'), 'missing proof root or checker');
  mkdirSync(join(directory, '.lake'), { recursive: true });
  const scratch = mkdtempSync(join(directory, '.lake', 'trust-'));
  try {
    // Lake owns dependency ordering. Explicit roots include files outside the
    // BoundaryV2 directory and orphan modules absent from the public root.
    const config = join(scratch, 'lakefile.toml');
    const roots = modules.map(m => m.name);
    writeFileSync(config, `name = "boundary_trust_check"\nversion = "2.0.0"\nsrcDir = ${JSON.stringify(directory)}\nbuildDir = ${JSON.stringify(join(directory, '.lake', 'build'))}\n[[lean_lib]]\nname = "BoundaryTrustCheck"\nroots = ${JSON.stringify(roots)}\n`);
    lake(directory, ['-f', config, ...(mutation ? [] : ['--wfail']), 'build', ...roots.map(n => `+${n}`)]);
    const file = join(scratch, 'Audit.lean');
    writeFileSync(file, `${roots.map(n => `import ${n}`).join('\n')}\nrun_cmd Lean.Elab.Command.liftCoreM (BoundaryTrust.audit #[${roots.map(n => '`' + n).join(', ')}])\n${replay ? 'run_cmd Lean.Elab.Command.liftCoreM BoundaryTrust.freshReplay\n' : ''}`);
    const output = lake(directory, ['-f', config, 'env', 'lean', '-DwarningAsError=true', file]);
    assert.deepEqual(discover(directory), modules, 'proof sources changed during checking');
    return output;
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    assert(process.argv.length === 2, 'usage: node semantics/v2/check.mjs');
    process.stdout.write(check());
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  }
}
