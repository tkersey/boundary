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

## Checked laws and their current scope

The five requested names are now Lean contract structures in
[`GeneralizedContracts`](BoundaryV2/GeneralizedContracts.lean), with no exported
inhabitants. Their checked components and required connections are:

| Export | Existing components | Remaining proof or connection |
| --- | --- | --- |
| `Defunctionalization.adequacy` | `stateful_initialization`, `stateful_response_entry`, ordinary adequacy, and the existing positive operand/entry drains | Prove stateful finite preservation/reflection; compose registry entry and exit/disposal with that observation relation. Ordinary adequacy remains a separate component. |
| `Handlers.interpretation` | Fresh installation, nearest selection, forwarding, context closure, actual resume/injection/successor correspondence | Use the stateful correspondence under arbitrary enclosing effectful handlers, including registered multi entry. |
| `UseScope.preservation` | Actual control/cell steps, typed consumption, physical capture multiplicity, scoped packages, registry insertion, fresh activation and dormant support | Connect registry and lifetime handoff across capture, activation, completion, and disposal. |
| `Exits.composition` | Stateful initiation, cancellation, ordered operands/failures, owned-result disposal, nested completion, region-to-cleanup-frame embedding | Connect region disposal during nested abandonment and compose exits with the source/target observation relation. |
| `OpenControl.observation_relocation` | Typed polling/rejection/admission, occurrence separation, authority, control and dormant-support relocation | Apply the same admission and relocation laws to the integrated registry/cleanup futures. |

These are explicit outstanding obligations, not claims discharged by compiling
the contract declarations. `GeneralizedContractChecks` checks the principal
field types and the stateful observation definitions; it constructs no contract
proof. The source/target finite observation definitions use their actual
permission-sensitive `ExecutionSteps`, retaining current resources at every
return, fault, yield, and request.

| Contract | Main proof surfaces | Checked content and limits |
| --- | --- | --- |
| D: defunctionalization | `GeneralizedValues`, `GeneralizedReification`, `GeneralizedOwnedOperandLowering`, `GeneralizedProgramSimulation`, `GeneralizedProgramObservations` | Closure/environment and context laws, recursive call unfolding, positive finite operand drains, and preservation/reflection of finite **ordinary** observations. Open requests retain related typed futures under every accepted response. Full stateful observation composition remains open. |
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
cells, regions, registry, and unrelated owning fields. `GeneralizedMultiEntry`
connects all three authored multi-resumption forms to finite positive target
entries. Injection completes operand evaluation and consumes the supplied
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

`GeneralizedNestedCleanup` executes nested protection boundaries with one shared
control/cell/region state. Saved parents retain typed return/unwind continuations
and exit records. Child completion restores the parent with current resources;
the parent is running again and receives no new initiation right. Nested body
failure details stay separate until the enclosing cleanup completes, preserving
the primary-before-details order and repeated equal faults. External cancellation
updates the outermost running cleanup's exit and preserves the active or captured
cursor. Abandonment follows the actual installed protection frames. Scope/region
completion rejects while any parent remains suspended.

Every finite ordinary target execution lifts into the driver. A three-level
checked run writes a cell, yields, is captured, receives repeated cancellation,
resumes, and fails; both parents keep the new cell contents, physical authority,
original failure, ordered nested failures, and first cancellation reason. Region
boundaries encountered during abandonment remain with their closing owner;
integration with the full registry and the general stateful observation theorem
is still unfinished.

The existing `DisposalRun` now enters and executes the nested driver while
retaining both the abandoned future's resume point and the disposal caller.
Only a finished nested machine can return its current runtime to unwinding;
there is no direct nested-to-resolved transition. A checked authored-dispose
example consumes its real grant, enters nested protection, waits through an
inner cleanup yield, finishes both cleanups, and reenters the original caller.
Its spent grant, unrelated owner, and existing caller-to-42 result are preserved.
The original flat-cleanup disposal proofs remain checked.

Running cleanup now also has a typed frame in the common source/target
continuation model. Normal protection completion enters cleanup beneath that
frame and the actual enclosing context. Requests therefore retain enclosing
handlers, and normal cleanup completion restores the saved body value before
the handler's return clause executes. Selection, forwarding, finite ordinary
observation preservation/reflection, capture provenance, relocation, and clone
views include the frame; a running cleanup cannot become a multi template.
A checked example distinguishes the cleanup's unit result, the saved integer
body value, and the enclosing handler's text answer.
`GeneralizedCleanupCompletion` now starts failure/cancellation cleanup under that
actual context and completes the running frame with the full exit record.
Nested failure details retain their order and original-failure precedence.
Cancellation updates the outermost running frame; the source/target context
updates correspond and leave resource state and current body diagnostics intact.
Abrupt completion examines actual owning fields. Nonowning aliases need no
disposal, while owned saved results stay in an explicit pending state. Returned
one-shot continuations use their real grants and saved futures for disposal,
preserving the enclosing exit and unrelated owners. A checked transition path
cannot propagate the exit before that disposal completes.
`GeneralizedValueDisposal` now extends that path to products, sums, packages,
closure captures, and nominal resource grants. It processes stored children in
order, checks actual active authority before disposing a view, and opens sealed
containers through the package/computation handoffs. Those handoffs also accept
the flattened transparent groups produced by control release. Structural steps
preserve store validity, exit information, cells, and spent-authority history;
active control cleanup retains the remaining queue. A composite package/closure
example consumes the intended grants in order, preserves an unrelated owner and
the original exit, and does not execute the closure body. The separate
continuation-only completion path is retired. Complete capture/lifetime
integration and general stateful adequacy remain unfinished.

`GeneralizedRegionDisposal` connects the existing oldest-cell handoff to that
same value-disposal queue. A disposal phase owns the current runtime; the region
handoff retains only its identity, continuation, and offered plain-cell names.
The current runtime returns after disposal, and the existing liveness/owner/alias
gate controls final storage retirement. `CleanupFrameSteps.of_region` embeds
every finite region run in the cleanup-frame driver. A checked path retains an
earlier plain cell, consumes the later value's real grant, rejects a surviving
cell alias, and then retires only the selected region while preserving outer
storage, unrelated authority, and the original exit history. Region handoff
during nested abandonment remains open.

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
on actual cleanup execution. `ScopeExit` and its completion laws remain because
the unwind and nested drivers still use them; their further integration is a
named X obligation, not grounds to delete them prematurely.

## Verification commands

From the repository root:

```sh
zig build check-v2-formal -Doptimize=ReleaseSafe -j2 --summary all
zig build check-v2 -Doptimize=ReleaseSafe -j2 --summary all
zig build check-v2-conformance -Dworld-source="$WORLD_CHECKOUT" -Doptimize=ReleaseSafe -j2 --summary all
```

For focused proof development, run `lake --wfail build` in this directory.
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
fresh replay. Six additional statement mutations reject `True` substitutions
for each required contract and an ordinary-only replacement for the source
stateful observation definition. The mutation step follows the proof build and
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
