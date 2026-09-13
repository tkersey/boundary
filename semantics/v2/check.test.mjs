// Copyright (c) 2026 Boundary contributors. MIT license.
import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check } from './check.mjs';

const project = fileURLToPath(new URL('.', import.meta.url));
function withProject(run) {
  const directory = mkdtempSync(join(tmpdir(), 'boundary-trust-mutation-'));
  try {
    copyFileSync(join(project, 'lean-toolchain'), join(directory, 'lean-toolchain'));
    copyFileSync(join(project, 'Trust.lean'), join(directory, 'Trust.lean'));
    writeFileSync(join(directory, 'BoundaryV2.lean'), 'import Std\ntheorem foundation : True := by trivial\n');
    mkdirSync(join(directory, 'Other'));
    run(directory);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

// Every probe is outside BoundaryV2 and absent from its imports and configured
// roots. The module-style probes also exercise Lean's private module section.
const probes = [
  ['clean private-module orphan', 'private theorem valid : True := by trivial', null, true],
  ['private unfinished proof', 'private theorem unfinished : True := by sorry', /unapproved axiom.*sorryAx/],
  ['hidden axiom', 'private axiom hidden : Nat\nnoncomputable def exposed : Nat := hidden', /unapproved axiom.*hidden/],
  ['unfinished definition', 'def unfinished : Nat := by sorry', /unapproved axiom.*sorryAx/],
  ['native evaluation', 'theorem native : (List.range 100).length = 100 := by native_decide', /unapproved axiom/],
  ['unsafe definition', 'unsafe def bypass : Nat := 1', /unsafe logical dependency.*bypass/],
  ['partial definition', 'partial def forever (n : Nat) : Nat := forever (n + 1)', /unsafe logical dependency.*forever/],
  ['private-module unfinished proof', 'private theorem hidden : True := by sorry', /unapproved axiom.*sorryAx/, true],
  ['private-module unused axiom', 'private axiom hidden : False', /unapproved axiom.*hidden/, true],
  ['spoofed recursive companion', 'def parent (n : Nat) : Nat := n\npartial def parent._unsafe_rec (n : Nat) : Nat := parent._unsafe_rec (n + 1)', /unsafe logical dependency.*parent/],
];
for (const [label, source, rejection, moduleStyle] of probes) {
  withProject(directory => {
    writeFileSync(join(directory, 'Other', 'Probe.lean'), `${moduleStyle ? 'module\n' : ''}import Std\nnamespace Elsewhere\n${source}\nend Elsewhere\n`);
    if (rejection) assert.throws(() => check(directory, { replay: false, mutation: true }), rejection, label);
    else assert.match(check(directory, { replay: true }), /trust replay:.*fresh kernel environment/);
    console.log(`trust mutation: ${label}: ${rejection ? 'rejected' : 'accepted and replayed'}`);
  });
}

withProject(directory => {
  // This is intentionally forged only in the isolated test project. The body
  // has no forbidden axiom, so rejection must come from fresh kernel replay.
  writeFileSync(join(directory, 'Other', 'Probe.lean'), [
    'import Lean',
    'set_option debug.skipKernelTC true in',
    'run_cmd Lean.Elab.Command.liftCoreM do',
    '  Lean.addDecl (.thmDecl { name := `forged, levelParams := [], type := Lean.mkConst `False, value := Lean.mkConst `True.intro })',
    '',
  ].join('\n'));
  assert.match(check(directory, { replay: false, mutation: true }), /positive axiom policy passed/,
    'kernel forgery must reach the replay gate');
  assert.throws(() => check(directory, { replay: true, mutation: true }),
    /while replaying declaration 'forged':[\s\S]*declaration type mismatch/,
    'fresh replay must reject a declaration inserted while kernel checking was disabled');
  console.log('trust mutation: skipped kernel checking: rejected by fresh replay');
});
