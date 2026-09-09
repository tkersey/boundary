// Copyright (c) 2026 Boundary contributors. MIT license.
// The proof gate discovers modules; Trust.lean discovers their declarations.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const project = fileURLToPath(new URL('.', import.meta.url));

function modulesIn(directory, prefix = ['BoundaryV2']) {
  const modules = [];
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.isSymbolicLink()) throw new Error(`proof source must not be a symlink: ${entry.name}`);
    if (entry.isDirectory()) modules.push(...modulesIn(join(directory, entry.name), [...prefix, entry.name]));
    else if (entry.isFile() && entry.name.endsWith('.lean')) {
      const parts = [...prefix, entry.name.slice(0, -5)];
      if (!parts.every(part => /^[A-Za-z_][A-Za-z0-9_]*$/.test(part))) {
        throw new Error(`unsupported Lean module path: ${parts.join('/')}`);
      }
      modules.push(parts.join('.'));
    }
  }
  return modules;
}

function lake(directory, args) {
  const result = spawnSync('lake', args, { cwd: directory, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.signal) throw new Error(`lake terminated by ${result.signal}`);
  return result;
}

function output(result) { return `${result.stdout ?? ''}${result.stderr ?? ''}`; }
function accepted(result) {
  if (result.status !== 0) throw new Error(output(result) || `lake exited ${result.status}`);
  return output(result);
}

function audit(directory, mutation = false) {
  const modules = ['BoundaryV2', ...modulesIn(join(directory, 'BoundaryV2'))];
  if (modules.length === 1) throw new Error('no formal-core source modules discovered');
  // Explicit module targets ensure an orphan file is compiled even if the root
  // module does not import it. Lean, not a regex over source, inventories proofs.
  accepted(lake(directory, [...(mutation ? [] : ['--wfail']), 'build', ...modules.map(name => `+${name}`)]));
  mkdirSync(join(directory, '.lake'), { recursive: true });
  const scratch = mkdtempSync(join(directory, '.lake', 'trust-'));
  try {
    const file = join(scratch, 'Audit.lean');
    const imports = modules.map(name => `import ${name}`).join('\n');
    writeFileSync(file, `${imports}\n${readFileSync(join(directory, 'Trust.lean'), 'utf8')}`);
    return lake(directory, ['env', 'lean', '-DwarningAsError=true', file]);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

function selfTest() {
  // Each probe is intentionally absent from BoundaryV2.lean and uses a different
  // namespace. Mutants live only in isolated copies, never in the user's tree.
  const probes = [
    ['clean orphan', 'namespace Elsewhere\ntheorem checked : True := by trivial\nend Elsewhere\n', false],
    ['private sorry', 'namespace Elsewhere\nprivate theorem unfinished : True := by sorry\nend Elsewhere\n', true],
    ['unused axiom', 'namespace Elsewhere\naxiom invented : False\nend Elsewhere\n', true],
    ['definition sorry', 'namespace Elsewhere\ndef unfinished : Nat := by sorry\nend Elsewhere\n', true],
    ['native decision', 'namespace Elsewhere\ntheorem native : (List.range 100).length = 100 := by native_decide\nend Elsewhere\n', true],
  ];
  for (const [label, source, reject] of probes) {
    const copy = mkdtempSync(join(tmpdir(), 'boundary-trust-'));
    try {
      cpSync(project, copy, { recursive: true, filter: path => !relative(project, path).split(sep).includes('.lake') });
      writeFileSync(join(copy, 'BoundaryV2', 'TrustProbe.lean'), `import Std\n${source}`);
      // Mutants must reach the axiom audit, not merely fail the warning gate.
      const result = audit(copy, true);
      if (reject) {
        assert.notEqual(result.status, 0, `${label}: the trust gate accepted a prohibited proof`);
        assert.match(output(result), /trust audit: unapproved axiom/, `${label}: failed for an unrelated reason`);
      } else accepted(result);
      console.log(`trust mutation: ${label}: ${reject ? 'rejected' : 'accepted'}`);
    } finally {
      rmSync(copy, { recursive: true, force: true });
    }
  }
}

try {
  const args = process.argv.slice(2);
  assert(args.length === 0 || (args.length === 1 && args[0] === '--self-test'),
    `usage: node ${basename(fileURLToPath(import.meta.url))} [--self-test]`);
  process.stdout.write(accepted(audit(project)));
  if (args.length) selfTest();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
