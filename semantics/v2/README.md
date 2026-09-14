# Generalized effects proof core

This is the in-progress replacement defined by [CONTRACT.md](CONTRACT.md).
Lean 4.33.1 with bundled Std checks a signature-parametric symbolic source and
its separately defined first-order representation. The complete five-contract
milestone remains unfinished; passing the current proof build does not establish
all of its acceptance requirements.

The source represents authored computations, lexical environments, effectful
clauses, and higher-order continuation functions. The target represents code,
closure environments, handler attachments, and return stacks as inspectable
first-order data. Its control fields contain no source-evaluator callbacks.
The translation is total over the typed source syntax. Pure leaf data and
primitive value-or-fault outcomes remain an explicit abstract interface;
internal control, resource, region, and ownership references are structural.

## Recovery checkpoint — 2026-09-14 (historical)

Recovery source: Codex thread `01a0887a-4487-7a31-b70e-7f0f37c8a1a0`,
persisted at
`/Users/tk/.codex/sessions/2026/09/09/rollout-2026-09-09T16-21-49-01a0887a-4487-7a31-b70e-7f0f37c8a1a0.jsonl`.
Recovery read bounded transcript chunks and directly relevant
records; it did not resume the old agent or alter its session files.
Implementation stopped at the user's recovery-only instruction at this checkpoint.
The active goal subsequently resumed; the current proof inventory below supersedes
this snapshot's failed-build status. The milestone remains unfinished.

### Objective and subsequent corrections

The accepted specification is the September 12 **Boundary — Generalized Effects
Proof Core**, read from
`/Users/tk/.codex/attachments/75e434fd-47f1-4fd6-b547-f1eb03f6e08b/pasted-text-1.txt`.
The old goal adopted it at `2026-09-12T13:31:17Z`. Complete D/H/U/X/O with
independent higher-order source and first-order target, total translation,
explicit local permissions, finite compositional proofs, positive trust checking,
and independent production conformance. Full-profile certification was withdrawn.
No merge, auto-merge, tag, release, World/Agent change, or public-format change is
authorized.

Subsequent user instructions, recovered directly from the transcript:

- September 12, `16:25:49Z`: approve unchanged World
  `87698f92ca7be4d5442e97ba27a2468aa3ff6a7c`; the previous pin rejected a required
  cleanup-disposal regression. `19:01:19Z`: publish available commits as a draft.
- September 14, `02:35:24Z` (byte offset `366530899`): continue on the existing
  branch/PR; no restart or reset to reference head `83d0911`. Define the five
  precise Lean claim types, connect existing results, and prioritize their
  missing semantic connections over more disconnected local results. Preserve
  capture provenance and the uninhabited-input counterexample, `NEG-000008`.
  Do not reopen the donors, narrow observations, assume the desired simulation,
  or replace independent source semantics with target execution.
- September 14, `03:10:01Z` (byte offset `370124219`): ablate superseded drivers
  and duplicate representations as part of integration. Preserve guarantees,
  meaning-bearing definitions, unfinished obligations, and distinguishing tests;
  imports/reference counts alone do not justify retention or deletion. No quotas,
  new framework, or separate cleanup project.

### Verified state and completed work

At recovery, `/Users/tk/workspace/tk/boundary` is clean on `main`,
`55e8feedcae0b9ee1492da11f9fbd4a1ac7ff328`. The implementation worktree is
`/Users/tk/workspace/tk/boundary-generalized-effects-proof-core`, branch
`codex/generalized-effects-proof-core`, HEAD
`387aa9d746e2bc94e3c85cca1d0c71da8ea957fe`. It was clean before the new-thread
attempt described below. [PR #149](https://github.com/tkersey/boundary/pull/149)
is open and draft at that exact head. Donor PRs #147/#148 are closed without
merging; their heads remain `b6e74aec` and `ce680c78`. Do not repeat supersession.

Recent commits already establish registered preservation/reflection
(`1d4578b`, `c259782`), shared handler-aware disposal frames (`8bcbf13`), finite
source cleanup preservation (`469fabe`), and source owned-value/control disposal
preservation (`387aa9d`). The specialized registered resume/clone drivers and
the separate nested-disposal/unwind wrapper were already retired. The inventory
below and [CONTRACT.md](CONTRACT.md) describe the precise checked components;
none of the five complete contract inhabitants is exported.

Historical validation on `387aa9d`: 185 Lean jobs; aggregate 444/444 steps and
99/99 tests; positive axiom audit, fresh kernel replay, 22 mutations; conformance
143 cases and 487 fresh native/WASM comparisons. Evidence remains in
`/tmp/boundary-source-owned-{aggregate,conformance}.log` and
`/tmp/boundary-source-owned-check-head.txt`. Live readback confirms
[CI run 34868126980](https://github.com/tkersey/boundary/actions/runs/34868126980)
succeeded for that commit. These are historical results, **not a pass for the
current dirty checkout**. The existing conformance checkout
`/tmp/boundary-world-generated-rAEXqm` was verified clean at the approved World
pin. Lean remains 4.33.1; historical integration tools were Zig 0.16.0 and Node
26.8.2. Refresh executable versions before new acceptance runs.

### Decision evidence and unfinished work

Ledger 1.2.1 read-only owner projections and doctors passed, with zero pending
transactions: eight Negative Ledger records and 43 Review Fold witnesses.
Negative Ledger revision is
`sha256:4baab308c3cbd514904f2d1f10e81e91876005f487cb30ae9dbbb13bdf5bcdf3`;
Review Fold revision is
`sha256:9bc08be1121072a7815643ca29375b8ac11a6b94920bdf13b27d7661fdb4b191`.
No Ledger records were changed. The 43 witnesses belong to an earlier goal;
their presence does not reinstate withdrawn proof obligations or prove current
liability. Recheck applicability through the owner before acting.

`NEG-000008` excludes deriving capture references/copy permissions from bare
callback equality over possibly uninhabited inputs; its discriminator remains
in `GeneralizedProvenanceExamples.lean`. Other recorded rejected routes include
unordered custody transport, fixed scope-entry owner lists, eager partial
operand transfer, and treating Drop permission as ownership classification.
Retain their relevant regressions. Whole-profile replicas/certificates and
same-dispatcher atom substitution remain excluded by the accepted specification.

Still required: source region/suspended-work rules and authored dispose entry;
reverse finite exit correspondence; joining exits with registered execution;
actual frame/registry/lifetime handoff through capture, activation, completion,
retained work and disposal; O on those integrated futures; complete D/H/U/X/O
inhabitants and their reviewed premises; exact-head final acceptance and review.
These are integration obligations, not a mandate for a production heap theorem.

### Last actions and exact resumption point

The old thread's last recovered tool action at `2026-09-14T16:24:19Z` polled the
PR-update process and queried CI. Its result confirmed the push and exact
draft/body readback; CI was then running. At `18:27:21Z` execution failed with
`context_window_exceeded`; remote compaction failed at `18:27:44Z`. Later retries
also failed. No uncommitted old-thread implementation remained at recovery.

Before the recovery-only clarification, a goal continuation in the **new** thread
started this preserved, uncommitted work:

- New `BoundaryV2/GeneralizedSourceCancellation.lean` (136 lines): source
  cancellation and attempted context/program correspondence.
- Modified `BoundaryV2/GeneralizedSourceExits.lean`: parked/captured cleanup and
  cancellation transitions.
- Modified `BoundaryV2/GeneralizedExitCorrespondence.lean`: associated relations
  and cancellation lemmas. `GeneralizedExitSimulation.lean` has **not** yet been
  extended for the new constructors.

The new module's first build failed; `/tmp/boundary-recovery-cancellation.log`
records the first error at line 15 (the `returned` pattern/binder), followed by
unresolved stack-induction and dependent `Option.Rel` goals. The dependent files
have not passed compilation. The build process terminated; no build is awaiting
polling. This checkpoint is the only additional documentation change; nothing
was committed or pushed during recovery.

**Resumption action recorded at recovery (subsequently completed):** re-read the three-file
diff, repair the first declaration error and cancellation correspondence proofs,
then run from the implementation worktree:

```sh
elan run leanprover/lean4:v4.33.1 lake -d semantics/v2 --wfail build +BoundaryV2.GeneralizedSourceCancellation
```

After that succeeds, extend the existing mutual exit simulation for the new
transitions and add a distinguishing captured-cleanup/first-reason regression;
check the affected contract consumers before broader acceptance. Choosing this
suspended-cleanup seam was the new thread's implementation judgment, not an
unrecorded instruction or completed result from the old thread. The named
`boundary-generalized-effects-proof-core-reorientation-spec.md` copy was not
located in the checked project/Downloads paths; use the verified attachment
above, rather than inventing another specification.

## Checked laws and their current scope

The five requested names are now Lean contract structures in
[`GeneralizedContracts`](BoundaryV2/GeneralizedContracts.lean), with no exported
inhabitants. Their checked components and required connections are:

| Export | Existing components | Remaining proof or connection |
| --- | --- | --- |
| `Defunctionalization.adequacy` | Core/registered preservation and reflection; finite source cleanup, value/control/region disposal and authored-disposal preservation | Complete normal-return region/scope composition, suspended-work abandonment, reverse exit correspondence, and the join with registered execution without omitting observations. |
| `Handlers.interpretation` | Fresh installation, nearest selection, forwarding, context closure, actual resume/injection/successor correspondence | Use the stateful correspondence under arbitrary enclosing effectful handlers, including registered multi entry. |
| `UseScope.preservation` | Actual control/cell steps, typed consumption, physical capture multiplicity, scoped packages, registry insertion, fresh activation and dormant support | Connect actual captured/unwound frame fields to registry and lifetime handoff across capture, activation, completion, and disposal. |
| `Exits.composition` | Shared handler-aware frame execution for disposal and nested cleanup, structured saved-result and handler-answer disposal, retained-root region handoff, current-resource completion, and finite embeddings | Connect suspended-work abandonment and registry/lifetime successors, then compose all exits with source/target observations. |
| `OpenControl.observation_relocation` | Typed polling/rejection/admission, occurrence separation, authority, control and dormant-support relocation | Apply the same admission and relocation laws to the integrated registry/cleanup futures. |

These are explicit outstanding obligations. D's current-execution preservation,
reflection, initialization, and response fields have checked defaults; no complete contract inhabitant
is exported. `GeneralizedContractChecks` checks the principal
field types and the stateful observation definitions; it constructs no contract
proof. The source/target finite observation definitions use their actual
permission-sensitive `ExecutionSteps`, retaining current resources at every
return, fault, yield, and request.

`GeneralizedSourceExits` supplies independent higher-order source cleanup entry
and completion, including normal return, authored failure, abandonment, and
owned saved results. Ongoing cleanup remains an ordinary source program under
its actual context. Its unwind runtime holds completed exit information;
unfinished work remains in the running source program rather than being marked
complete. No source transition executes target code.

`GeneralizedExitCorrespondence` relates current heaps, cells, regions, original
values, and outside contexts. Finalization admission preserves and reflects the
source's return/exit/owned-disposal decision. `GeneralizedExitSimulation` lifts
the local correspondences and existing core simulation over every constructor
and arbitrary finite derivations of the current source cleanup relation. It
reuses `open_program_context`; the duplicate context-opening helper developed
during integration was removed. `GeneralizedExitContextView` supplies only the
finite target administrative-prefix drains needed to reach the actual frame.
Those drains preserve current resources, and exit entry/completion then takes
a positive target step.

D's `cleanup_preservation` and `cleanup_observations` fields have checked
defaults. The latter distinguishes all four observations and relates scoped
bodies and suspended futures through the existing observation relation. The
source regressions derive a cleanup yield beneath an enclosing handler and
retain an owned saved result across extra target administrative frames. These
are source-derived expectations, not calls to the target evaluator.

Source cleanup now enters actual value disposal for owned saved results.
`Source.ValueDisposalStep` processes products, sums, packages, closure captures,
resource grants, and owned continuations; `Source.ControlProgressStep` executes
source cleanup and disposes returned answers. The three source relations recurse
through one another while retaining pending queues and current resources. Their
target correspondences use the existing package/computation handoffs, authority
consumption, context support, and value-reference mapping laws.

The preservation proof uses Lean's generated mutual induction principle.
Its recursive hypotheses concern strictly contained derivations; no runtime
fuel, target execution premise, or new assurance framework is introduced.
`finite_value_disposal_preserved` and `finite_control_disposal_preserved` supply
D's corresponding fields. The existing cleanup/observation preservation proof
now covers those operations too. Source-derived regressions consume a saved
result before propagating failure, release a package's resource and closure
captures in declared order, and execute a disposed continuation's source cleanup.
They preserve unrelated ownership and exact spent-grant history. The existing
trust harness rejects a source resource rule that forgets the spent authority.

`GeneralizedSourceCancellation` independently locates the source's outermost
running cleanup, including inside a requested or yielded future. Cancellation
preserves its actual body, saved result, and first accepted reason. Its context
and program laws relate both accepted cancellation and absence of a running
cleanup to the target operation, including target administrative callers.
D's `running_cancellation` and X's `source_first_cancellation` fields consume
these results.

The existing finite exit simulation now includes running/parked/captured
cancellation, yield parking/continuation, capture, and reattachment. Two unwind
helpers name their actual cleanup successor instead of depending on exclusivity
of the source transition. A source-derived trace composes handler-aware cleanup
entry with capture, repeated cancellation, reattachment, parking, and continuation;
it preserves the original failure, first reason, running future, and unrelated
owned grants. Trust mutations reject overwriting that reason and discarding
the running body. Registry custody and abandonment of suspended work are still
separate unfinished connections, not implied by the location correspondence.

Source unwinding now enters `Source.RegionDisposal` inside the same mutual
cleanup/value/control relation. The source owns its current cell table and
higher-order outside context. Offering a cell transfers its real owning field;
nonowning storage remains readable until retirement. Source and target independently
collect surviving roots, then use the existing pure storage-admission predicate.
`GeneralizedSourceRegionCorrespondence` proves entry, offer, return, and retirement
correspondence; `finite_region_disposal_preserved` supplies D's region field.
The source-derived regression disposes two owning cells in creation order,
rejects a surviving cell alias, preserves unrelated ownership/outer storage, and
composes region exit through the parent cleanup to a related target failure.

`GeneralizedSourceDisposalExecution` connects the existing authored source
`DisposeEntry` to those actual shared operations. Operand evaluation precedes
authority consumption, and the disposal caller remains separately retained.
`finite_authored_disposal_preserved` supplies D's authored-disposal field for
arbitrary finite runs, including operand failure, cleanup, value/control/region
work, and final return/failure/cancellation. Source unwinding skips ordinary bind
and handler frames without invoking their callbacks. The target reuses one finite
execution embedding for ordinary work, operand failure, and disposal entry.
A Boolean-input continuation's yielding cleanup finishes before its original
integer caller resumes with unit and returns 42; the target result is derived
from that independent source run. New mutations reject omitted caller roots,
omitted region outside roots, and premature removal of still-readable cells.

This is a preservation component, not complete cleanup adequacy. The source
cleanup relation still needs normal-return region/scope composition, suspended-work
abandonment, and its connection to registered execution; reverse finite correspondence must
cover those operations as they are integrated. It is not enough that the
present relation and its currently implemented constructors compile.

`GeneralizedStateSimulation` composes all current source execution constructors:
ordinary/context steps, cell operations, owned control and effectful clause
entry, fresh handlers/protections/regions, packages, and ordered operands. It
recovers the actual target caller from `ProgramRelated`, including administrative
return frames and the authored bind description. The neutral operand bridge
proves that the ordinary gate uses the same store-preserving operand work as the
owning evaluator. No simulation premise is assumed. Finite source derivations
then preserve observations and related current resources. Both head-observation
directions are checked, including finite source forwarding through running
cleanup. A source-derived owned-closure call followed by yield instantiates the
general theorem and checks the spent grant, all three remaining physical owners,
and its typed future. This closes the current stateful preservation field; it
does not supply missing registry/exit transitions or complete target-derived reflection.

`GeneralizedStateReflection` now inverts actual finite target operand execution.
Its generic law covers every expression and argument constructor, including
owned/shared closure allocation and primitive failure after a successful prefix.
The inverse recovers the source evaluation and related updated store; successful
expressions and failed argument prefixes leave strictly shorter target runs.
Every computation uses this same operand-prefix result through
`computation_operands_observing_run_reflected`, which supplies D's checked
`operand_reflection` field. Return expressions additionally have complete finite
observation reflection. A six-instruction target-only regression allocates an
exclusive closure and fails in a later operand; reflection recovers the source
fault, fresh closure grant, captured owner, unrelated owner, and related cells.
The close-instruction views only expose existing typed code, operands, and the
caller for inversion; they define no additional interpreter. The broader
ordinary-step inverse replaces the initial plain-operand-only helper. Remaining
receiving-instruction and context reflection still block the full D claim.

`GeneralizedControlReflection` now recovers source cell reads/writes/allocation,
package/unpackage, one-shot resume/injection/successor, closure application, and
fresh handler/protection/region entry from the actual target transition. Each
inverse preserves the related current resources and caller and returns a shorter
observing target run. Field handoffs are reflected through body translation;
copyability, owning occurrences, consumed grants, capture partitions, and actual
lookup results retain their existing meaning. The application inverse composes
with the generic operand-prefix inverse for arbitrary authored functions and
arguments, including operand failure, and supplies D's `application_reflection`
field. Its target-only stored-closure regression consumes grant 8, retains owner
100 and captured owner 6, and yields beneath the retained caller. The inspection
view for application exposes existing typed operands; it adds no evaluator.
The existing configuration reindexing lemma is reused by both ordinary and
stateful reflection. The common receiving-instruction/context composition is
now assembled below; registry/exit integration remains unfinished.

`GeneralizedFiniteReflection` assembles the operand and receiving-instruction
inverses and inducts over arbitrary finite target executions. It reconstructs
source transitions under binds, effectful handlers, regions, protections, and
running cleanup frames. Return, authored failure, yield, and pending requests
retain their corresponding current resources and typed futures. No simulation,
runtime fuel, or universal termination premise is assumed. Separate template,
disposal, and exit drivers still need their required embedding; the current
relation's inability to execute those entries is explicitly not whole-core
adequacy evidence.

This composition exposed a source-model gap: a root request with a matching
handler in its saved context had a target dispatch but no source step. The source
now selects across `saved.append around` and invokes its existing physical
capture operation. `OwnedStep.handled` is a general derived case for syntactic
handlers; there is one source request-dispatch rule, with no reattachment loop.
The selectors preserve their independent implementations and have explicit
reconstruction and nearest-prefix laws on the needed sides. Source handledness
excludes external opening independently. The old handler-specific
`ProgramRelated.handler_request_view` and `ExecutionStateRelated.handler_request_view`
helpers are removed; shared context/selection laws supply their role. The
syntactic and saved-handler regressions reuse one effectful clause tail, retain
the same seven source and seventeen target steps, consume the new authority once,
and preserve both older owners. The general finite inverse is instantiated on
the complete saved-handler target trace and its final text request.

| Contract | Main proof surfaces | Checked content and limits |
| --- | --- | --- |
| D: defunctionalization | `GeneralizedValues`, `GeneralizedReification`, `GeneralizedProgramObservations`, `GeneralizedStateSimulation`, `GeneralizedFiniteReflection` | Closure/context laws, recursive call unfolding, finite ordinary adequacy, and finite preservation/reflection for the current permission-sensitive relation. Open requests retain related typed futures and current resources. Registry/disposal/exit embedding remains open. |
| H: handlers | `GeneralizedSelection`, `GeneralizedForwarding`, `GeneralizedHandlerEntry`, `GeneralizedControlExecution`, `GeneralizedSuccessor`, `GeneralizedInjectionExecution`, `GeneralizedFreshHandlerExecution` | Nominal selection and forwarding, deep/shallow capture, effectful clause entry, distinct body/answer types, successor handling, non-tail resumption, and use-site injection have local correspondence laws. Installation computes fresh support-aware identities. Remaining scoped and multi-use composition is unfinished. |
| U: use and scope | `GeneralizedFields`, `GeneralizedOwnership`, `GeneralizedControlStore`, `GeneralizedScopes`, `GeneralizedScopeCapture`, `GeneralizedResources`, `GeneralizedTemplates`, `GeneralizedStateExecution` | Actual owning occurrences preserve multiplicity across control stores, closures, cells, and retained containers. Local transfer, one-shot consumption, packaging, release, scope/borrow, resource-authority, and computed template-instantiation laws are checked. Stateful region entry is connected to cell allocation. Full lifetime closure and remaining activation/composition laws are open. |
| X: exits | `GeneralizedOperandPrefix`, `GeneralizedExit`, `GeneralizedStatefulCleanup`, `GeneralizedExitCompletion`, `GeneralizedUnwinding`, `GeneralizedRegionRetirement` | Ordered handoff, retained cleanup cursors, single initiation, first cancellation reason, failure precedence, cleanup completion, and finite outer-unwinding order are checked. Cell-held control can transfer into saved-context disposal; plain cells remain readable for later cleanup. Final region/resource lifetime closure remains open. |
| O: observation and relocation | `GeneralizedInteraction`, `GeneralizedObservations`, `GeneralizedCodeRelocation`, `GeneralizedOwnedRelocation`, `GeneralizedExitRelocation`, `GeneralizedRuntimeSupport` | Local laws distinguish logical request openings from polling, preserve typed response reentry, and transport finite supported identities through values, code, captures, and control stores. Full composition over the remaining stateful mechanisms is unfinished. |

`BoundaryV2.lean` exports the generalized modules and their distinguishing
examples. The older `Lowering`, `Control`, `ControlLowering`, `Ownership`,
`Regions`, and `Effects*` models are retired from the active tree. Their single
operation family, pure-clause/shared-dispatcher interpretation, and sole-token
custody model are not used to justify the generalized claims. Their source
remains available at baseline commit
`55e8feedcae0b9ee1492da11f9fbd4a1ac7ff328` and in the donor history. The ordinary
production regressions remain active, including State/Choice, recursive calls,
non-tail handlers, and disposal/transfer cases.

Local capture/support and lifetime premises delimit the claims. The core does
not prove that every production source checker or saved-state validator
establishes them. Borrowed references remain distinct from physical owners;
copyability of a computation does not grant permission to duplicate exclusive
captures or exit obligations. Consistent relocation is a logical renaming law,
not a codec or hash-injectivity theorem.

Package and unpackage now execute in the common control/cell state through
`GeneralizedPackages` and `GeneralizedPackageExecution`. Packaging transfers the
operand's actual owning fields into a fresh-grant container; unpacking consumes
only that outer grant before returning its contents. The package and cell
operations share `GeneralizedValueHandoff`. Borrow retention and lifetime checks
remain separate scope obligations; sealing a value does not extend its lifetime.

`GeneralizedFreeze` connects owned target control to the existing reusable
instantiator. It takes the actual registered future, selects current local cells
and dormant records using the capture owner's explicit partition, and publishes
the consumed successor only after copy-safety admission succeeds. Identity
return frames are removed from the clone view; the source-context relation and
all pending protections are preserved. Tests cover emitted clone entry,
reentrant fresh names, shared outer cells, and refusal of exclusive captures or
cleanup obligations.

`GeneralizedCaptureDescription` retains the authored bodies and environments
that produced higher-order source callbacks. Source bind nodes now store this
provenance beside the executable function and preserve it through capture and
yield. Equal functions alone cannot recover it: an uninhabited-input regression
has equal callbacks with different capture permissions. Actual source futures
now distinguish those captures, and their reference support is unique.
Every context already related by
the core has such a description; its compilation preserves copyability and
reference occurrences after removing target identity frames.
`GeneralizedSourceTemplates`, `GeneralizedSourceFreeze`, and
`GeneralizedFreezeExecution` independently admit source templates, prove exact
agreement with target freeze success or refusal, and connect authored clone
operands to a finite positive target drain and the returned template binding.
Acquisition in the ordinary source heap yields the same actual callback future
and consumed successor, and the source branching fixture compiles to the
existing target fixture. Descriptions supply explicit authored provenance.

`GeneralizedSourceRelocation` renames arbitrary typed source expressions,
bodies, and clauses and proves that compilation commutes with that operation.
`GeneralizedSourceActivation` computes fresh names from source support and
rebuilds its callbacks from the renamed bodies and environments. Compiling the
result yields exactly the independently instantiated target future, cells,
dormant aliases, and active branch inventory. Checked reentrant source runs
preserve current shared state, keep branch writes separate, and execute the
actual source callback against its branch cell.

`GeneralizedTemplateRegistry` retains typed immutable bindings and rejects
rebinding an existing identity. `GeneralizedRegisteredFreeze` returns the
consumed successor together with its registered template. Registered resume,
injection, and successor functions instantiate the stored template against the
current arena; source/target correspondence preserves the resulting future,
cells, regions, registry, and unrelated owning fields. `GeneralizedRegisteredExecution`
embeds ordinary execution, clone registration, and all three multi-resumption
forms into one runtime. `GeneralizedMultiControlEntry` proves finite positive
target entries on that relation. Injection completes operand evaluation and consumes the supplied
closure's authority before entering its actual body; successor clauses retain
their effectful computations and separate body/answer types. Checked examples
cover owned captures, a yielded injected body, and a changed-answer successor.
Dormant records retain complete private snapshots, including their cells,
local names, and nested owned captures. Nominal reference edges can still form
aliases or cycles. Parent activation relocates the whole captured forest and
registers its templates atomically; each later child activation copies only its
private snapshot and uses current outer state. Duplicate bindings and exclusive
captures reject without publishing a partial registry. General registration
laws preserve existing lookups, and the freshness proof includes nested private
cells. The nested source/target example checks a child snapshot, current parent
and shared cells, and a back-reference to an existing child binding.
Allocation/retirement across the complete registry lifetime remains unfinished;
these local laws do not close the whole-core milestone.

The registered runtime supplies registry, dormant, and active support to the
existing core rules. Ordinary closure/control creation, cell allocation, fresh
installation, and multi-entry operands therefore reserve retained identities.
Current cells remain in the arena once; `withState` writes back each actual
successor, and `Steps.from_core` lifts arbitrary finite core runs with unchanged
retained support. Source/target support correspondence preserves the distinction
between these nonowning roots and physical grants. `MultiRuntimeRelated` uses
the existing structural program relation and projects to `ExecutionStateRelated`.

This retires the specialized `ResumeRun`, both `CloneEntry` relations, both
`CloneResult` wrappers, and `GeneralizedMultiEntry`. Their operand, handoff,
template, caller, and region laws now use registered steps; the source/target
freeze algorithms remain independent. The connected clone/resume regression
executes six source steps and sixteen target steps to the same return, keeping
the registry and current shared cell. Another regression allocates cell 8 while
cell 7 exists only in a retained template, and keeps current cell 2. No source
oracle or production mapping changed.

`GeneralizedRegisteredSimulation.registered_observation_preserved` now supplies
D's `registered_preservation` field. It composes every current registered source
transition over arbitrary finite derivations, retaining related registry/arena
state and all four observation forms. The existing core preservation argument
now accepts arbitrary retained support; core and registered entries share its
structural caller relation. Clone uses the actual related target heap, including
noncanonical administrative frames. `Context.captureMetadata` projects the
authored fields already stored in source frames and is a proved left inverse
of `Capture.future`; this connects the captured source description to the
target clone view without recovering permissions from bare callback equality.
The uninhabited-input counterexample and `NEG-000008` remain intact. A regression
derives the complete clone/resume observation from general preservation when
the target heap has an extra silent frame.

`GeneralizedRegisteredReflection.registered_observation_reflected` supplies
D's `registered_reflection` field. It derives the independent source execution
from an arbitrary finite target run, including clone, all three multi entries,
effectful handlers, and saved contexts. `OperandTraceLaws` states only two local
target-step inversion facts, proved for both drivers; it contains no source
execution or translation premise. One operand induction now serves both
drivers and ordinary/described source heap views. Shared receiver inverses
replace their former observing-run-specific implementations; the common core
computation theorem retains those results. The source description projection
and operand mapping preserve actual fields, grants, and callback provenance.
A target-only clone/resume trace regression recovers the source observation
and retained ownership state through the general theorem. Disposal and
exit/lifetime integration remain required before declaring the milestone complete.

`GeneralizedScopeClosure` checks actual surviving fields, code, returned values,
and saved control before detaching a lifetime subtree. Source and target checks
agree. Registered runtimes include their retained templates and dormant/active
futures automatically. `GeneralizedLifetimeExit` performs that check only after
cleanup finishes and preserves its exact resolution and exit history. Examples
retain owned work past creator closure and reject younger dependencies in
fields, future code, stored closures, and template registries.
`GeneralizedRegionClosure` now retires selected region storage and liveness
together after cleanup completes. It checks actual remaining cell owners and
surviving references in returned values, callers, retained/disposal futures,
other cells, and declared external roots. General laws preserve physical owner
multiplicity, unrelated cell reads, and exact exit information, and exclude
aliases to retired cells or regions. The higher-order return operation agrees
with the target operation, including refusal, and preserves the state relation.
Examples reject pending/captured cleanup, live linear cells, and stale aliases;
successful failure/cancellation exits retain their history and continuation.
`GeneralizedScopedRegions` associates each region with its nominal owning scope.
Registration rejects rebinding and unknown scopes; moving or retaining a scope
preserves its associations. The combined close derives its region set from the
actual detached subtree, checks complete agreement with runtime liveness without
requiring binding-list order, and publishes scope, bindings, storage, and
liveness together. General laws keep the resulting bindings valid, remove every
closed scope's region, and preserve regions owned by retained work. Examples
connect the ordinary computed region identity to registration and retain a
child's storage after creator closure. Complete lifecycle integration, including
registry allocation/retirement and nested captured cleanup, remains unfinished.

`GeneralizedDisposal` and `GeneralizedDisposalExecution` connect an authored
one-shot dispose operand to authority release and its actual saved unwind
context. The local driver retains the caller separately, waits through cleanup
suspension, and returns unit only after abandonment completes. Cleanup failure
and cancellation retain their distinct outcomes. The remaining nested
cleanup/lifetime composition still belongs to the unfinished X contract.

Disposal now uses the same handler-aware frame driver as ordinary cleanup.
`ControlProgress` runs the actual abandoned future under `CleanupFrameSteps`;
`DisposalRun` retains the disposal caller separately. Cleanup starts beneath
`cleanupReturn` and the live enclosing stack. Normal and abrupt completion,
handler clauses, non-tail callers, region handoff, and nested value disposal
therefore use the same continuations and current resources. The independent
source/target ordinary execution and disposal-entry correspondence remain
proved components.

`GeneralizedExitWork` holds the shared frame/control/region/value states and
operations, and `GeneralizedExitTransitions` holds their recursive transitions.
`GeneralizedCleanupCompletion` supplies their completion and composition laws.
The former `NestedProgress` family, separate nested states in `DisposalRun` and
`ValueDisposal`, and the disposal wrapper over `UnwindSteps` are removed.
Their finite prefix and current-resource guarantees now use
`ControlProgressSteps.of_frames`, `DisposalRun.frame_steps`, and
`ValueDisposalSteps.of_control`. The old completed-run-only nested constructor
remains removed. No file is excluded from declaration discovery or replay.

Running cleanup retains its saved body value and actual enclosing handlers.
The original source/target context, selection, capture-provenance, relocation,
and no-cloning-a-running-cleanup laws remain. A new disposal regression reaches
its enclosing nominal handler while distinguishing cleanup's unit result, the
handler's text answer, and the disposal caller's integer result. The existing
normal-cleanup example also retains the original integer body value before the
handler's return clause runs. The ordinary and nested disposal regressions now
execute the common frame transitions, retain the spent grant and unrelated
owner, and return to the original caller-to-42 computation only after cleanup.

Frame completion preserves the current store, cells, and live regions on both
normal and abrupt paths. Its exit records retain original-failure precedence,
ordered nested failures, and the first cancellation reason. Owned saved body
results enter explicit disposal; they cannot be skipped while propagating an
exit. A returned handler answer also enters the actual value-disposal queue
before disposal returns unit to its caller. This includes arbitrary typed owned
answers; a regression consumes the answer's real resource grant first.

`GeneralizedValueDisposal` processes products, sums, packages, closure captures,
resource grants, and saved continuations through their actual owning occurrences.
It checks current active authority before disposing a view and uses the existing
package/computation handoffs for sealed contents. Structural steps preserve
store validity, exit information, cells, and spent-authority history. Control
disposal retains the remaining queue through every frame prefix. The composite
package/closure regression preserves declaration order, an unrelated owner, and
the original exit without executing the closure body. A nested-yield regression
keeps the next resource grant live until the current cleanup finishes, then
consumes it in order.

`GeneralizedRegionDisposal` uses the same queue for actual oldest-cell handoff.
Earlier plain cells remain readable while later owned cells are disposed. The
current runtime returns to the same continuation; the existing physical-owner,
reference, and liveness gate controls storage retirement. Region steps include
the live enclosing frame references, and disposal callers and pending values
supply their actual retained roots. Optional external roots cannot replace them.
An eight-step nested-region regression preserves outer storage and spent
authority. A saved cell alias in an actual parent `cleanupReturn` frame blocks
retirement. The trust mutation rejects omission of retained caller roots.

X's `frame_completion`, `frame_region_handoff`, `retained_region_roots`,
`frame_disposal_embedding`, `control_value_embedding`, and `control_answer`
fields have checked defaults. They are local composition laws, not an exported
inhabitant of the final X contract. The earlier standalone lifecycle and nested
capture/abandonment laws remain checked while their remaining ownership and
lifetime connections are resolved. Suspended-work abandonment, handoff of
scope-owned frame fields, registry/lifetime successors, and full source/target
observation correspondence remain open.

The outer unwind, cleanup-frame, and region handoff operations now use the
completion condition owned by `Resolution`. Pending, running, and captured
cleanup cannot be skipped to start outer work or dispose region cells. The
unwind transition relation enforces the same condition, including its terminal
case. General rejection laws cover arbitrary unfinished cursors; the completed
region and cleanup paths remain checked.

The standalone `ScopeProgress`, `ScopeStep`, and `ScopeSteps` wrapper is removed.
It re-expressed `beginReturnedProtection`/`beginFailedProtection`, `RuntimeSteps`,
and `finish` without adding a required interpretation. Its normal-return and
captured-cleanup/write/cancellation regressions now assert those operations
directly with the same inputs, initiation count, final resources, continuation,
and exit. `RuntimeSteps.finished_never_restarts` states the no-restart consequence
on actual cleanup execution. `ScopeExit` and its local lifetime laws remain for the named unfinished
registry/lifetime and suspended-work connections. They are not the execution
path used by authored disposal.

## Verification commands

From the repository root:

```sh
zig build check-v2-formal -Doptimize=ReleaseSafe -j2 --summary all
zig build check-v2 -Doptimize=ReleaseSafe -j2 --summary all
zig build check-v2-conformance -Dworld-source="$WORLD_CHECKOUT" -Doptimize=ReleaseSafe -j2 --summary all
```

For focused proof development, run `lake --wfail build` in this directory.
From the repository root, use
`elan run leanprover/lean4:v4.33.1 lake -d semantics/v2 --wfail build`;
`lake -d` alone selects the invoking directory's toolchain before changing directories.
`check-v2-formal` discovers project modules, enforces logical trust, runs trust
mutations, and performs fresh kernel replay. `check-v2` includes that gate and
the existing Boundary-only checks. World is required only by the explicit
conformance command. Ordinary compiler/data imports continue to require only Zig.

`check.mjs` discovers every project `.lean` file except generated `.lake`
contents. Explicit Lake roots build orphan files even outside `BoundaryV2`.
`Trust.lean` uses Lean's declaration provenance and follows types, bodies, and
inductive constructors transitively. Private declarations and unused definitions
are included. The only permitted axioms are `propext`, `Quot.sound`, and
`Classical.choice`. Unsafe or partial logical definitions reject; recognized
executable companions of safe recursive definitions contribute no logical
permission to depend on unsafe code. The checker is executable tooling and
cannot become a semantic dependency.

Fresh replay uses Lean 4.33.1's `Lean.Environment.replay` API with an empty
kernel environment at trust level zero. The isolated mutation suite accepts a
valid orphan and rejects private unfinished proofs, hidden axioms, unfinished
definitions, native-evaluation dependencies, unsafe definitions, and partial
definitions. It also covers private declarations in Lean's module system and a
spoofed recursive-companion name. A forged declaration inserted with kernel
checking disabled deliberately passes the axiom-only control and must fail
fresh replay. The statement/definition mutations reject `True` substitutions
for each required contract and an ordinary-only replacement for the source
stateful observation definition, plus core-only replacements for source and
target registered observations, omitted retained caller roots, and loss of
source cleanup failure history/cancellation, and forgotten spent authority. The mutation step follows the proof build and
uses an isolated compiled-module overlay. Completing the contract proofs and
reviewing all remaining semantic connections are still open; logical trust and
statement checking do not establish the entire milestone.

## Production correspondence

The ordinary bridge uses public-builder programs, the normal compiler and
encoding path, an independent source oracle, and the user-approved unmodified
World commit `87698f92ca7be4d5442e97ba27a2468aa3ff6a7c`. It compares complete
native/WASM outcomes in fresh instances, preserves observable event order,
checks polling and response rejection, and alternates the restored backend.

The [fixture interpretation map](../../test/v2/core_mappings.md) covers all 41
baseline source programs, their distinguishing observations, and static refusal
counterparts. The [reproducible generated sample](../../test/v2/generated_programs.md)
maps the additional 16 programs. Conformance also rejects an earlier valid
response at a later typed request and requires the scripted terminal outcome;
an unfinished source or runtime run cannot count as success.
The [Linux workflow](../../.github/workflows/lean.yml) pins the
tools and World dependency and records clean proof-build and test costs.

These are kernel-checked laws about the Lean core and executable tests of the
production implementation. They are not universal Zig/World refinement,
verified BPI bytes, complete borrow inference, environmental correctness,
universal termination, or global replay protection. Whole-profile operational
replicas, codec/hash/schema theories, and production certification tooling are
excluded from this milestone, not deferred prerequisites.
