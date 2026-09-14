// Copyright (c) 2026 Boundary contributors. MIT license.
import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { check } from './check.mjs';

const project = fileURLToPath(new URL('.', import.meta.url));

// Compile only the changed module and its statement consumers in an isolated
// search-path overlay. Dependencies come from the preceding proof build; no
// production source, shared olean, or working tree is mutated by a probe.
function claimMutations() {
  const directory = mkdtempSync(join(tmpdir(), 'boundary-claim-mutation-'));
  const contracts = readFileSync(join(project, 'BoundaryV2', 'GeneralizedContracts.lean'), 'utf8');
  const observations = readFileSync(join(project, 'BoundaryV2', 'GeneralizedStateObservations.lean'), 'utf8');
  const registered = readFileSync(join(project, 'BoundaryV2', 'GeneralizedRegisteredExecution.lean'), 'utf8');
  const exits = readFileSync(join(project, 'BoundaryV2', 'GeneralizedExitTransitions.lean'), 'utf8');
  const cleanup = readFileSync(join(project, 'BoundaryV2', 'GeneralizedCleanupCompletion.lean'), 'utf8');
  const sourceExits = readFileSync(join(project, 'BoundaryV2', 'GeneralizedSourceExits.lean'), 'utf8');
  const sourceCancellation = readFileSync(join(project, 'BoundaryV2', 'GeneralizedSourceCancellation.lean'), 'utf8');
  const exitSimulation = readFileSync(join(project, 'BoundaryV2', 'GeneralizedExitSimulation.lean'), 'utf8');
  const consumers = readFileSync(join(project, 'BoundaryV2', 'GeneralizedContractChecks.lean'), 'utf8');
  try {
    mkdirSync(join(directory, 'BoundaryV2'));
    const artifacts = join(project, '.lake', 'build', 'lib', 'lean', 'BoundaryV2');
    for (const name of readdirSync(artifacts)) {
      if (!/\.olean(?:\.|$)/.test(name) || /^(GeneralizedContracts|GeneralizedContractChecks|GeneralizedStateObservations|GeneralizedRegisteredExecution|GeneralizedExitTransitions|GeneralizedCleanupCompletion|GeneralizedSourceCancellation|GeneralizedSourceExits|GeneralizedExitSimulation)\./.test(name)) continue;
      symlinkSync(join(artifacts, name), join(directory, 'BoundaryV2', name));
    }
    copyFileSync(join(project, 'lean-toolchain'), join(directory, 'lean-toolchain'));
    const environment = { ...process.env, LEAN_PATH: [directory, join(project, '.lake', 'build', 'lib', 'lean')].join(process.platform === 'win32' ? ';' : ':') };
    function compile(name, source, emit = false) {
      const file = join(directory, 'BoundaryV2', `${name}.lean`);
      writeFileSync(file, source);
      const result = spawnSync('lean', ['-R', directory, ...(emit ? ['-o', file.replace(/\.lean$/, '.olean')] : []), file],
        { cwd: directory, env: environment, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
      if (result.error) throw result.error;
      return { status: result.status, output: `${result.stdout ?? ''}${result.stderr ?? ''}` };
    }
    function accepted(result, label) {
      assert.equal(result.status, 0, `${label}\n${result.output}`);
    }
    function rejected(result, label) {
      assert.notEqual(result.status, 0, `${label}: weakened claim was accepted`);
      assert.match(result.output, /error(?:\([^)]*\))?:.*(?:Invalid field|Function expected|Type mismatch|type mismatch|Application type mismatch|unsolved goals|Tactic `rfl` failed)/s, label);
      console.log(`trust mutation: ${label}: rejected by statement checking`);
    }
    accepted(compile('GeneralizedExitTransitions', exits, true), 'original shared exit transitions');
    accepted(compile('GeneralizedCleanupCompletion', cleanup, true), 'original cleanup composition laws');
    accepted(compile('GeneralizedStateObservations', observations, true), 'original stateful observations');
    accepted(compile('GeneralizedRegisteredExecution', registered, true), 'original registered execution');
    accepted(compile('GeneralizedSourceCancellation', sourceCancellation, true), 'original source cancellation');
    accepted(compile('GeneralizedSourceExits', sourceExits, true), 'original independent source exits');
    accepted(compile('GeneralizedExitSimulation', exitSimulation, true), 'original source exit simulation');
    accepted(compile('GeneralizedContracts', contracts, true), 'original contract declarations');
    accepted(compile('GeneralizedContractChecks', consumers), 'original contract consumers');
    for (const [namespace, name] of [
      ['Defunctionalization', 'adequacy'], ['Handlers', 'interpretation'],
      ['UseScope', 'preservation'], ['Exits', 'composition'], ['OpenControl', 'observation_relocation'],
    ]) {
      const start = contracts.indexOf(`structure ${name} : Prop where`);
      const end = contracts.indexOf(`\nend ${namespace}`, start);
      assert(start >= 0 && end > start, `missing ${namespace}.${name} mutation target`);
      const replacement = `def ${name} (_signature : Signature) (_algebra : LeafAlgebra _signature.Data)\n` +
        '    (_program : List (BodyType _signature.Data _signature.Effect)) : Prop := True\n';
      accepted(compile('GeneralizedContracts', contracts.slice(0, start) + replacement + contracts.slice(end), true),
        `${namespace}.${name} to True probe must itself compile`);
      rejected(compile('GeneralizedContractChecks', consumers), `${namespace}.${name} replaced with True`);
    }
    const stateful = '∃ count, ExecutionSteps (retained := retained) table before count after ∧ HeadObservation after.control.computation observation';
    assert(observations.includes(stateful), 'missing stateful observation mutation target');
    // Change only the meaning-bearing definition. Connected semantic proofs may
    // now reject the mutation before the separate statement consumer runs.
    const ordinaryOnly = observations.replace(stateful, 'Observes table before.control.computation observation');
    const mutated = compile('GeneralizedStateObservations', ordinaryOnly, true);
    if (mutated.status === 0) {
      accepted(compile('GeneralizedContracts', contracts, true), 'contracts over weakened observation relation');
      rejected(compile('GeneralizedContractChecks', consumers), 'stateful observation replaced with ordinary-only observation');
    } else {
      rejected(mutated, 'stateful observation replaced with ordinary-only observation');
    }
    accepted(compile('GeneralizedStateObservations', observations, true), 'restored stateful observations');
    const registeredObservation = '∃ count, Steps table before count after ∧ Source.HeadObservation after.control.computation observation';
    assert(registered.includes(registeredObservation), 'missing registered observation mutation target');
    const restrictedSource = compile('GeneralizedRegisteredExecution', registered.replace(registeredObservation,
      'Source.StateObserves table before.state after.state observation'), true);
    if (restrictedSource.status === 0) {
      accepted(compile('GeneralizedContracts', contracts, true), 'contracts over restricted registered observations');
      rejected(compile('GeneralizedContractChecks', consumers), 'registered observation replaced with core-only observation');
    } else {
      rejected(restrictedSource, 'registered observation replaced with core-only observation');
    }
    const registeredTargetObservation = '∃ count, Steps table before count after ∧ Target.HeadObservation after.control.configuration observation';
    assert(registered.includes(registeredTargetObservation), 'missing registered target observation mutation target');
    const restrictedTarget = compile('GeneralizedRegisteredExecution', registered.replace(registeredTargetObservation,
      'Target.StateObserves table before.state after.state observation'), true);
    if (restrictedTarget.status === 0) {
      accepted(compile('GeneralizedContracts', contracts, true), 'contracts over restricted registered target observations');
      rejected(compile('GeneralizedContractChecks', consumers), 'registered target observation replaced with core-only observation');
    } else {
      rejected(restrictedTarget, 'registered target observation replaced with core-only observation');
    }
    const retainedRoots = 'RegionDisposal.finish (retained ++ external) before = some after';
    assert.equal(exits.split(retainedRoots).length, 2, 'expected one nested retirement mutation target');
    accepted(compile('GeneralizedExitTransitions', exits.replace(retainedRoots,
      'RegionDisposal.finish external before = some after'), true), 'retained-root omission probe must itself compile');
    rejected(compile('GeneralizedCleanupCompletion', cleanup), 'cleanup region retirement omits retained caller roots');
    accepted(compile('GeneralizedExitTransitions', exits, true), 'restored shared exit transitions');
    const sourceDiagnostics = '⟨.failure fault, diagnostics.failures, diagnostics.cancellation⟩ outside';
    assert.equal(sourceExits.split(sourceDiagnostics).length, 2, 'expected one source cleanup diagnostic mutation target');
    accepted(compile('GeneralizedSourceExits', sourceExits.replace(sourceDiagnostics,
      '⟨.failure fault, [], none⟩ outside'), true), 'source cleanup diagnostic omission probe must itself compile');
    rejected(compile('GeneralizedExitSimulation', exitSimulation), 'source cleanup entry discards failure history and cancellation');
    const spentAuthority = 'token :: runtime.store.fields.spent';
    assert.equal(sourceExits.split(spentAuthority).length, 2, 'expected one source resource-disposal mutation target');
    accepted(compile('GeneralizedSourceExits', sourceExits.replace(spentAuthority,
      'runtime.store.fields.spent'), true), 'source spent-authority omission probe must itself compile');
    rejected(compile('GeneralizedExitSimulation', exitSimulation), 'source resource disposal forgets spent authority');
    const runningCancellation = 'some (.cleaning identity original (exit.cancel reason) first)';
    assert.equal(sourceCancellation.split(runningCancellation).length, 2, 'expected one source running-cancellation mutation target');
    rejected(compile('GeneralizedSourceCancellation', sourceCancellation.replace(runningCancellation,
      'some (.cleaning identity original { exit with cancellation := some reason } first)')),
    'source cancellation overwrites the first accepted reason');
    rejected(compile('GeneralizedSourceCancellation', sourceCancellation.replace(runningCancellation,
      'some (.cleaning identity original (exit.cancel reason) (.returned (.datum .unit)))')),
    'source cancellation discards the running cleanup continuation');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

claimMutations();
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
