// Copyright (c) 2026 Boundary contributors. MIT license.
import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check } from './check.mjs';

const project = fileURLToPath(new URL('.', import.meta.url));
// These minimal projects run the real discovery/build/audit path. Every probe
// lives outside BoundaryV2 and is absent from its imports and configured roots.
const probes = [
  ['clean orphan', 'theorem valid : True := by trivial', null],
  ['private unfinished proof', 'private theorem unfinished : True := by sorry', /unapproved axiom.*sorryAx/],
  ['hidden axiom', 'private axiom hidden : Nat\nnoncomputable def exposed : Nat := hidden', /unapproved axiom.*hidden/],
  ['unfinished definition', 'def unfinished : Nat := by sorry', /unapproved axiom.*sorryAx/],
  ['native evaluation', 'theorem native : (List.range 100).length = 100 := by native_decide', /unapproved axiom/],
  ['unsafe definition', 'unsafe def bypass : Nat := 1', /unsafe logical dependency.*bypass/],
  ['partial definition', 'partial def forever (n : Nat) : Nat := forever (n + 1)', /unsafe logical dependency.*forever/],
];
for (const [label, source, rejection] of probes) {
  const directory = mkdtempSync(join(tmpdir(), 'boundary-trust-mutation-'));
  try {
    copyFileSync(join(project, 'lean-toolchain'), join(directory, 'lean-toolchain'));
    copyFileSync(join(project, 'Trust.lean'), join(directory, 'Trust.lean'));
    writeFileSync(join(directory, 'BoundaryV2.lean'), 'import Std\ntheorem foundation : True := by trivial\n');
    mkdirSync(join(directory, 'Other'));
    writeFileSync(join(directory, 'Other', 'Probe.lean'), `import Std\nnamespace Elsewhere\n${source}\nend Elsewhere\n`);
    if (rejection) assert.throws(() => check(directory, { replay: false, mutation: true }), rejection, label);
    else assert.match(check(directory, { replay: true }), /trust replay:.*fresh kernel environment/);
    console.log(`trust mutation: ${label}: ${rejection ? 'rejected' : 'accepted and replayed'}`);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}
