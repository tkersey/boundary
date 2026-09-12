# Checked core and its current proof boundary

This is a model of Boundary control and lowering, checked with the pinned
Lean 4.33.1 toolchain and bundled Std. It has no external package dependencies.
Run `lake build` for elaboration, or `zig build check-v2-formal` from the
repository for discovery, enforced trust, mutations, and fresh kernel replay.
`check-v2-semantics` includes that formal gate. Importing Boundary's
Zig modules does not execute these commands or require Lean.

The artifacts under proof are the Lean definitions here. The production Zig
compiler and World interpreter are not Lean programs. Restricted artifact
bridges bind complete scalar-projection and lexical-closure source artifacts to final
production BPI2 bytes. Separate execution certificates bind complete World
invocation records to the independently defined target machine. The complete
source language still lacks a checked translation relation to that machine;
its correspondence is tested by the independent source oracle and runtime conformance.

| File | Checked claims |
| --- | --- |
| Lowering.lean | Typed lexical expressions with Unit, Boolean, mathematical Nat, products, de Bruijn variables, and bind compile to explicit first-order instruction lists. `compile_preserves_value_and_scope` proves result equality, unchanged caller environment, and unchanged operand-stack tail for every expression, environment, and stack. |
| Control.lean | Typed context composition; selection by explicit attachment identity; exact reconstruction of both sides of a selected delimiter; deep/shallow capture; no second return-clause application to clause answers; preservation of non-tail postprocessing; operation progress to a selected delimiter or a residual operation. |
| ControlLowering.lean | An independently defined stack of first-order blocks preserves source context values, composition, attachment selection, and deep/shallow capture. `compilation_preserves_non_tail_resume` combines these properties. `return_step_simulation` and `return_trace_simulation` relate each return transition and any finite sequence of such transitions. |
| Ownership.lean | Fresh/live/spent token invariants; consumption preserves disjoint unique ownership; a consumed token cannot resume again; multi activations obtain distinct control identities; lexical region entry and checked exit preserve scope. |
| Regions.lean | Immutable local-cell templates; consistently renamed local references; reads from current outer storage; alias and scope preservation; distinct names under disjoint fresh maps; multi activation preserves scope and ownership; freezing consumes the original token. |
| Effects.lean | A complete finite effectful machine: effects on either side of bind, branches, explicit capability environments, nested deep/shallow handlers, non-tail clause callers, immutable multi templates, region reads/writes, and residual resume/dispose/transfer. `machine_progress`, `tick_preserves_invariants`, and `transition_preserves_invariants` cover every control constructor. |
| EffectsLowering.lean | All embedded lexical expressions compile into first-order instruction blocks, including expressions in dormant nested templates. `effectful_step_simulation` and `effectful_trace_simulation` preserve transitions and complete finite observable traces. `drive_preserves_invariants` extends ownership preservation to any accepted external script. |
| EffectsExamples.lean | Kernel reductions establish deep/non-tail result 114, shallow/non-tail result 104, direct operation-clause answer 7, the two State/Choice results `(1,1)` and `(1,2)`, effectful binds across two residual responses, and consumed sender custody on disposal/transfer. Compiled examples independently reduce to the same expected values. |
| EffectsIdentity.lean | Derived initialization reserves above ambient attachments. The `[0]`/fresh `0` regression satisfies old custody, intercepts under raw construction, rejects under checked construction, and stays residual under derived initialization. |
| EffectsSelection.lean | Exact reconstruction, requested attachment, first matching active delimiter, absence equivalence, and append laws on `Effects.Stack`, preserving all frame data and typed components. |
| EffectsActivation.lean | Concrete allocator intervals, restricted injectivity, disjoint successive intervals, selection equivariance for reserved requests, complete nested reference remapping, and a dormant-alias regression. These are local allocator laws, not full machine well-formedness preservation. |
| EffectsWellFormed.lean | Checked initialization and every internal/external transition preserve custody, reserved attachment support, distinct active delimiters, and recursively valid dormant templates on the indexed Effects machine. State-sampling and event scripts preserve the same predicate. Repeated aliases remain valid; colliding initial supply and duplicate dormant delimiters do not. |
| EffectsEvents.lean | Separate state samples and transition events; rejection and polling emit no events; script composition concatenates events; genuine equal requests retain distinct occurrences; atom lowering preserves event steps and traces. |
| ProjectionArtifact.lean | Complete staged-source and nine-section BPI2 encodings for scalar constants and parameter projections, independent source lookup and target-slot execution, target slot well-formedness, nonempty argument domains, and all-input correspondence bound to exact artifact bytes. |
| LexicalArtifact.lean | Exact source/image binding for a closure that captures a `u64` input and adds a literal argument. Independent lexical evaluation and BPI2 block transitions agree for every admitted input, including authored overflow; evaluation is deterministic, terminal paths are unique, and finite completion excludes infinite target successor streams. |

The original small-model inventory is covered by the following construction and
theorems. Type and scope preservation are intrinsic: `Flow` indexes lexical
variables, capability evidence, region count, and result type; each `Position`
contains a heap with exactly its indexed region count and a typed stack to the
same root scope/result. A cell reference is a `Fin` index into that heap.
`tick` is total over this complete typed control state. There is no stuck or
unchecked-cast alternative. The additional `Machine.Valid` predicate requires
unique, disjoint live/spent token sets and exact custody: the pending position
owns the sole live token, and every other state owns none.

| Required formal observation | Evidence |
| --- | --- |
| Type, scope, and linear-ownership preservation | Indexed `tick`/`transition` results; `tick_preserves_invariants`, `transition_preserves_invariants`, and `drive_preserves_invariants`. |
| Progress up to residual effects | `machine_progress`; `live_residual_progress` proves each typed residual disposition has a valid successor. |
| Simulation into first-order code | `compile_preserves_value_and_scope`, `effectful_step_simulation`, and `effectful_trace_simulation`. |
| Return, bind, deep/shallow handling, non-tail resume | Every corresponding `Flow`/`Frame` constructor participates in the global step/trace proofs; closed examples distinguish the return-clause and non-tail rules. |
| Regions and linear/multi disposition | `LocalHeap` stores only the captured prefix; `rebasing_preserves_current_outer_heap`; exact one-shot custody and `residual_disposition_consumes_once`; multi activation and nested template remapping are covered by the global simulation. |

The effectful core uses one mathematical `Nat -> Nat` operation family with
arbitrarily many explicit instances. Its bind bodies can perform effects.
Handler return clauses and clause postprocessors are pure; clause plans dispose,
resume once, or fold a finite list of reusable resumptions. The control algebra
is shared by the source and target instantiations. Compilation replaces every
source expression with typed instruction data; it does not claim a separately
derived production interpreter or flatten the whole model into BPI2 blocks.
`initial body capabilities` now derives the natural-number attachment supply.
`initialWithSupply?` rejects an insufficient supplied bound. `rawInitial` remains
raw data construction and receives only a custody theorem. `Machine.Valid`
continues to mean custody; it is not a proof of global identity/scope preservation
or of a serialized graph's complete admission rules.

`Effects.Machine.WellFormed` combines that custody predicate with attachment
identity preservation. The state indices establish type and cell-scope
compatibility. Every capability occurrence, active delimiter, pending or
transferred request, and recursively nested dormant template lies below the
allocation supply. Each active delimiter spine and each dormant template has
distinct delimiter allocations; repeated capability aliases are permitted.
The actual activation renaming preserves these conditions, and its newly
activated delimiters are disjoint from the outside stack. Checked initialization,
`tick`, every accepted external transition, rejected attempts, and complete
scripts preserve `WellFormed`. The raw colliding initialization satisfies the old
custody predicate but fails this one. Atom lowering preserves the same stronger
predicate, including all dormant templates. These are general preservation theorems
for the indexed Effects machine; the production-shaped source and target
machines still need their own complete preservation proofs.

The separate `Regions.lean` model uses number-valued cells and explicit local/outer references.
Fresh-name injectivity and disjointness are hypotheses of the corresponding
renaming theorems. No theorem silently assumes those properties of an arbitrary
allocator. The clone-safe modeled template types have no exclusive resources or
exit obligations. The ownership ledger models logical custody, not serialized
allocation history or the entire portable ownership graph. Transfer consumes
the sender's custody; an independent receiver graph is outside this model.

General fixed-width arithmetic faults, recursive application code, arbitrary effectful
operation clauses, first-class suspension packages, scoped forwarding,
cleanup/cancellation, graph cycles, complete canonical wire codecs, garbage collection,
and selective compiler optimizations have separate executable evidence and are
outside this formal core. Finite script lengths in `drive` and the closed-example
`ticks` helper are observation horizons; no machine transition reads semantic fuel.
`driveStateSamples` names the original sampling behavior. `driveEvents` records
new events caused by accepted transitions, including logical request occurrence
IDs. These IDs do not change any production protocol record.

## Enforced trust

`tools/v2/formal.mjs` discovers all formal `.lean` files outside build/cache
directories. Only `Trust.lean` is tooling. A discovered module missing from the
built import closure rejects, and project imports absent from discovery reject.
Declaration ownership comes from Lean module provenance, including private
bodies and generated declarations. Types and bodies are traversed with explicit
missing-dependency failure. Reports include source hashes and are published only
after the source snapshot is rechecked.

`Trust.lean` permits only `propext`, `Quot.sound`, and `Classical.choice`; it
rejects project axioms even when unused, placeholders, unsafe/partial semantic
definitions, opaque executable meanings, and semantic dependencies on tooling.
The pinned compiler generates executable `_unsafe_rec` companions for some
safe definitions. They are identified together with a safe, same-typed parent,
reported separately, and cannot occur in any logical dependency closure.
Their existence does not authorize native computation as proof.

The aggregate replays the stored declarations with Lean 4.33.1's bundled
`leanchecker --fresh`. Negative controls cover admission, custom/unused axioms,
native decision, private definitions, orphan/generated/missing modules, malformed
reports, suppressed warnings, unsafe/partial definitions, colliding allocation,
missed dormant remapping, and duplicate polling events. Each mutation must fail
for its expected reason in an isolated copy; clean sources are checked again.

## Restricted production artifact proofs

```sh
zig build build-v2-certification-compiler
zig-out/bin/boundary-certify-compile \
  --source complete-source.json --image final.bpi2 --witness candidate.json
zig build check-v2-certification-inputs
zig build check-v2-projection-artifacts
zig build check-v2-lexical-artifacts
```

The paired compiler reads a source artifact once, uses an exact integer and
duplicate-rejecting reader, and compiles that decoded Module through the ordinary
lowerer, custody normalization, direct optimization, canonicalization, and
encoder. Its optional observer owns copies of all four pass outputs. The 37
baseline fixtures are checked for identical ordinary and observed final bytes.
These pass snapshots are untrusted candidate data, not certificates.

The projection gate compiles six parameter/constant programs, including multiple
parameters and `u64` maximum, and creates fixed-template Lean declarations in
`.cache/certification`. `ProjectionArtifact.check_sound` derives each exact-byte
claim and its all-input relation. The audit verifies the actual claim type and
both byte arrays; fresh replay checks generated declarations. Mutations replace
the claim with `True` or an input-restricted statement, introduce native proof
authority, omit a declaration, reuse a stale subject, or corrupt a final constant.

The lexical gate checks the existing `lexical` fixture and two variants with
literal arguments zero and `u64` maximum. Source evaluation captures a lexical
environment; target execution uses constructor capture slots, jumps, application,
a return stack, and result holes. Their ordinary and overflow outcomes agree
for all admitted inputs. The independent source oracle also exercises arithmetic
boundary cases. Replacing the captured variable or the certificate claim rejects.
The natural-number fragment is connected under an established representability
condition; the complete fixed-width claim includes the overflow branch.

These are intermediate proofs of restricted, complete source shapes. Byte
interpretation uses exact encodings, with explicit catalogs and every section;
the restricted artifact checkers do not yet establish a full-profile translation
relation. The conclusions concern function results and the lexical family's target paths, without protocol,
cancellation, or World execution-segment guarantees. The other 36 baseline
source fixtures do not yet receive program certificates.

The production-shaped source transition machine now covers the staged AST's
control constructors, scalar/container instructions, closures, deep/shallow and
successor handlers, one-shot/multi captures, regions/cells, resource borrowing,
ordered operand custody, disposal, protection, suspended cleanup, and external
cancellation. `test/v2/source_machine.mjs` compares its execution of all 37 source
fixtures and 122 environmental scenarios with the independent JavaScript
source oracle, including 10,000 recursive calls and cancellation during disposal
of a protected continuation. The source-derived constructor catalog is compared
with every raw compiler witness. Two additional compiled probes exercise raw
`computation` and `constant` instructions, including the implicit unit literal
introduced by explicit disposal. The test runner's step limit is an explicit
inconclusive tooling limit; the logical transition relation has no execution
fuel. Cancellation has one machine owner, so nested cleanup cannot overwrite
the first reason. These executed checks do not replace general admission,
well-formedness preservation, or source/target simulation proofs.

`SourceResults` independently derives every staged term's optional result type,
including abrupt branches, binding failure, sum matches, product unpacking and
recursive calls. Finite result-table witnesses have a unique meaning: ordinary
kernel proofs establish equivalence between local row checking and inference,
including all unreachable term declarations. Combined frontend checks also
validate schemas, references, function results, lambda shape and exact lexical
captures; the entry function has no free variables. `SourcePrimitives`,
`SourceDeclarations`, and `SourceContracts` additionally check every primitive
signature and authored fault list, closure bounds, effect and handler declarations,
higher-order calls, resumptions, protection, and region contracts. Schema rules,
primitive rules and dependency analysis share a language-indexed implementation;
source checks consume source syntax and lexical facts, never a target control graph.
The finite syntax scan has kernel proofs that accepted function contracts and
resource authority cover every child and nested operand. Source initialization
requires these typing checks. The execution cohort rejects missing/altered result
rows, malformed primitive operands and faults, and invalid control/declaration
interfaces. Source use/borrow preservation and general machine well-formedness
remain separate unfinished obligations.

`SourceUsage` additionally checks ordered reads and consumption at every function
body before initialization. It rejects reusing an affine closure after its first
call, requires linear consumption on every normal return path, permits repeated
use of reusable closures, and ignores unused syntax rows. The normal-return
check preserves failure paths that release ownership through unwinding.
The borrowing classification comes from the source machine's primitive rules.
Checked regressions distinguish these cases; this admission check does not yet
prove full custody or borrow preservation during execution.

`SourceBorrowGraph` derives a dependency graph directly from source syntax and
checked lexical captures. References are local to each function and respect
shadowing; failed branches retain their writes. `SourceBorrowPaths`,
`SourceBorrowMapping`, `SourceBorrowSources`, `SourceBorrowQueries`, and
`SourceBorrowRequirements` track selected fields, closure captures, handler
state and captured environments, shallow successor returns, cells, and calls.
Source initialization requires a closed borrow witness. Every requested query
and function summary must exist, and the checker rebuilds the source graph.
The untrusted candidate search has explicit inconclusive limits; its success
does not replace the ordinary checker. `BorrowLifetime` owns the fresh-lifetime
rule shared by source and target, with separate source and target projections.

The admission cohort preserves 54 valid sources and rejects all 12 younger
handler aliases written through return clauses, including state, body-result,
selected-product-field, and delegated-call variants. It also rejects 1,607
altered or incomplete witnesses. Ordinary theorems establish local dependency
closure, required-summary coverage, fresh-owner rejection, and the initializer's
borrow-check requirement. They do not yet establish global interprocedural
summary soundness or borrow preservation by every source transition.

The source-machine laws now connect concrete capture instantiation to handler
selection, exact copied objects, frozen local storage, and unchanged outside
lookups. Cell read/write laws preserve physical identity and every other cell.
Initialization excludes runtime handles and custody tokens from admitted entry
arguments, including recursive containers. Ambient requests allocate distinct
occurrence counters. These local laws do not establish full `WellFormed`
preservation or source/target simulation.

`SourceAllocationLaws` proves that every accepted source transition preserves
all allocation frontiers and heap inventory lengths, then lifts the result to
arbitrary finite transition sequences. `SourceObligationLaws` proves that every
existing obligation remains at its original heap index and follows the cleanup
lifecycle throughout those same source transitions. Its identity, lexical scope,
creation order, cleanup value, and protected resource remain fixed. A started
cleanup cannot restart, and a completed or failed cleanup cannot complete again,
including after external responses, cancellation, or reusable activation. These
theorems use the full source dispatcher; they do not assume global machine
well-formedness or replace the remaining typing, borrow, and simulation proofs.
`SourceIdentityExecution` proves that every initialized source execution keeps
all retained attachment, region, cell, lexical-scope, invocation, and obligation
metadata below the corresponding allocation frontier. This covers active frames,
all heap records and objects, dormant captures, frozen-cell metadata, and loans.
The proof follows every actual internal and external transition, including fresh
capture instantiation, clause handoff, cleanup, disposal, and cancellation. It
uses successor allocation counts to bound fresh identities without assuming
successor well-formedness. Together with `SourceIndexLaws`, these bounds establish
that the current scope and invocation have their exact indexed records; the same
lookup lemmas cover bounded scope, invocation, and obligation references elsewhere.
They do not yet prove lexical ancestry, owning-location validity, active
attachment uniqueness, borrow lifetime, progress, or full source well-formedness.
`SourceHandoffLaws` proves that handled requests enter clause code in the same
transition as the custody transfer. Every owned body has a holding in the entered
clause scope, and that holding owns its token in the actual custody book. Function
entry establishes the same fact for every owned argument. The source conformance
gate cancels immediately after both owned-body handoffs in the scoped-reader
fixture, requiring ordinary unwind to finish with an empty custody book; the
previous deferred invocation left a linear body stranded at a future receiver.
This correction affects the proof-only source transition granularity and retains
the independent oracle's semantic trace.
Cancellation derives running cleanup from the obligation lifecycle, including
when a handled operation captures the cleanup's return frame. The general
`cancellation_waits_for_running_obligation` theorem preserves its control,
status, and custody while recording the first cancellation. The writer/raise
conformance case cancels throughout that captured-cleanup window and requires
the running obligation to complete with no remaining custody. A stack-only
activity test previously interrupted the captured cleanup and reached an
invalid unwind rule.
`SourceRequestLaws` additionally proves that every finite source trace contains
exactly the consecutive request-opening identities allocated during that trace.
Those identities are unique even when payloads are equal. Parked polling,
terminal polling, result acceptance, and cancellation rebinding contribute no
new request opening; observing a pending state late invents no earlier event.

`SourceIndexLaws` proves that scope, invocation, and obligation records keep
their exact table indices across every initialized source trajectory, including
copied capture records. `SourceCustodyBounds` proves that live custody tokens
and object references remain below their allocation frontiers throughout those
trajectories. The actual allocator always succeeds under these bounds, and
later allocations use distinct tokens from earlier live entries, including
entries that have since been consumed. `SourceCloneSafety` proves that one-shot
conversion consumes the original tokens, reusable activation preserves the
custody book, and nested dormant templates receive the same structural and
live-custody checks. `SourceCustodyAlignment` connects each live token in a
value to the physical object recorded by the custody book, while admitting
stale lexical values after consumption. Allocation, transfer, and consumption
preserve this alignment; allocation, transfer, consumption, and replacement
preserve live objects. Retirement preserves live objects when its consumed
reference is aligned. Current aligned references therefore resolve to live
objects, and token-free renaming preserves alignment. These local laws support
the global reference-safety theorem below.
Complete typing and borrow preservation remain separate obligations.

`Primitives.evaluate_preserves_references` proves that every successful pure
primitive preserves arbitrary predicates of reference schemas, physical nodes,
and custody tokens. It covers the complete opcode dispatch, including container
updates and optional extraction results; stateful graph actions remain explicit
machine operations. `SourcePrimitiveCustody` applies that theorem to token bounds
and token-to-object alignment and proves alignment through the atomic ownership
commit that delivers the result.

`SourceValueInventory` includes every semantic value stored in source control,
frames, heap objects, dormant captures, scope holdings, cleanup records, and
status. Renaming maps the complete frame and capture inventories, including
deferred disposal results and cleanup failures. Term entry, operand evaluation,
temporary storage, and external actions preserve predicates of those values.
`SourceReferenceState` combines token-to-object alignment, bounds on all retained
tokens, and live custody objects into `State.OwnedReferenceWF`. Public
initialization establishes this component. `SourceReferenceSafetyExecution`
now derives it after every actual internal/external source execution from that
initialization. The proof includes spent tokens retained in lexical remnants,
cloned closure contents, and suspended cleanup; its constants come from checked
source admission, including the derived unit constant used for disposal.

`SourceReferenceContracts` separates usable reference compatibility from the
ownership mode of each nested reference. `ReferenceStructure` additionally
follows the catalog through products, sums, and containers to those leaves. It concerns
reference traits; finite scalar, byte, and container admission remains governed
by the unchanged `ValueShape` and byte checkers. `SourceCopyValues` derives
token-free values and closure captures for every
copyable value or closure reached through ordinary initialized execution.
`SourceReferenceStructureExecution` derives those catalog paths and ownership
modes from ordinary successful initialization and actual source `Steps` across
all values, including dormant captures, heap contents,
cleanup information, and external interactions. This does not assume finite
container or cancellation-payload bounds. Those bounds remain separate parts
of `ValueShape`.
`SourceReferenceStorage` and `SourceReferenceClone` prove local compatibility
preservation for allocation, movement, replacement, retirement, and the actual
capture-instantiation map. Retirement uses custody alignment and the reference
modes to protect other usable references. `SourceCloneOwnership` now proves that actual stored-template instantiation
preserves usable reference compatibility, token-to-object alignment, and live
custody throughout the resulting state and capture. The proof follows the actual
support walk through closure environments, local cells, and dormant templates;
it derives their capture and catalog facts from initialized source execution.
`SourceReferenceSafety` composes the reference obligations for initialization,
external input, allocation, movement, replacement, retirement, and pure primitive
commit. Its storage, control, capture, effect, and cleanup modules cover every
actual transition, including caller values retained across retirement and reusable
activation. `initialized_execution_preserves_reference_safety` proves usable
reference compatibility, token-to-object alignment, token bounds, and live
custody for every initialized source execution. Together with the separately
proved custody bounds, `initialized_execution_owned_reference_wf` establishes
`State.OwnedReferenceWF`. Typing, lexical ownership, borrowing, and cleanup
obligations remain separate parts of full source well-formedness.

`SourceTokenInventory` through `SourceTokenExecution` establish bounds on every
retained custody token through ordinary initialization and all actual source
steps. This includes spent tokens in lexical remnants, cloned values, dormant
captures, and cleanup data. Every historical token remains below each later
allocation supply, so a new allocation cannot revive a retained old token.
These bounds are proved independently of global token-to-object alignment.

`SourceCaptureTypes` derives each lambda capture's type from its checked
variable interface and declared capture bound. The closure creation operation
checks the actual captured values against that interface. Copy, clone, and drop
traits of a computation therefore entail the corresponding trait of each
captured value's schema; this does not yet establish typing of the entire heap.

`ValueTyping` gives a finite typing derivation for every admitted external
value and propagates structural traits to reference leaves. `TraitCompleteness`
proves that every safe trait is accepted within the existing finite catalog
bound. `SourceValueTypes` connects these results to the actual allocation modes:
a typed copy-safe value has no owned tokens, including in aggregate fields and
closure captures. `SourceValueExecution` proves this finite value-typing component
through every initialized internal and external transition, including primitive evaluation,
reusable activation, cancellation, and suspended cleanup. Complete heap, scope,
and frame compatibility remain separate obligations.

`TraitImplications` proves that clone safety entails copy safety, including
recursive computation and resumption dependencies. A typed clone-safe value
therefore has no owned tokens. `SourceEnvironmentTypes` proves that both scope
creation paths, function entry, and lexical binding preserve declared variable
types. `SourceExpressionTypes` proves value-shape preservation for the complete
expression-entry dispatcher, deriving lambda interfaces and literal admission
from the checked source context.
`SourceControlTypes` proves preservation through function entry, closure
application, lexical binding, pattern entry, the control-term dispatcher, and
invocation return. `SourceLifetimeTypes` proves that extracting live owned
leaves, leaving lexical scopes, releasing holdings, and disposing values
preserve value shapes, including reinstated one-shot cleanup frames. These
local results supply the full value-typing induction. Complete heap, scope,
and obligation compatibility remain separate obligations.
`SourceCaptureValueTypes` proves preservation by the actual capture-instantiation
path, including copied objects, frozen local-cell substitution, dormant
captures, reference renaming, and newly allocated scopes.
`SourceEffectTypes` proves preservation by the complete effect-term dispatcher:
request capture, direct clauses, handler installation, value and computation
resumption, and region entry. It also covers handler completion and restored
resume callers. The capture and resumption claims derive their value inputs
from the predecessor state; they do not assume the successor is well-typed.
`SourceCleanupValueTypes` proves value-shape preservation for the cleanup-term
dispatcher, protection installation, cleanup completion and failure, and cleanup
entry. `SourceInformationTypes` derives the type of the actual cleanup-information
record from its checked layout and typed failure values. The actual constructor
checks payload sizes against the profile's 64-bit length limit and validates text
reasons. An unrepresentable size returns an operational `capacity` rejection with
no committed successor; it does not become an authored failure.
`SourceInformationCapacity` checks both sides of the exact length boundary,
malformed text, and absence of a successor after oversized cleanup preparation.
`SourceUnwindTypes` proves preservation through the full unwind path without
caller-supplied size or cancellation-validity premises. `PrimitiveValueTypes`
proves typing for the shared arithmetic, bitwise, conversion, comparison, natural,
optional, collection, blob,
and slice constructors, deriving fixed-array bounds from schema admission.
`IntegerTextTypes` checks the exact decimal byte construction for every supported
integer width: ASCII UTF-8 with at most 21 bytes, including a possible minus sign.
`PrimitiveEvaluatorTypes` proves the complete pure primitive dispatcher preserves
finite value typing, using actual instruction admission to rule out resizing a
fixed array during either pop operation. `PrimitiveResultSchema` separately
proves every successful pure result has the instruction's declared schema.
`SourcePrimitiveTypes` proves finite value typing for every source heap operation
and the full source primitive execution path, with an explicit premise that
actual operand schemas satisfy instruction admission. Constructor schemas come
from admitted source lambdas, including the derived constructor table, and the
implicit unit constant is checked against the source catalog.
`SourcePrimitiveResults` proves that a delivered primitive result has the
instruction's schema across both pure and heap execution. Full frame and heap
compatibility remain open.
`SourceEnvironmentInventory`, `SourceEnvironmentEffects`, and
`SourceEnvironmentExecution` prove that every lexical binding in running code,
stack frames, closures, and captured continuations retains its declared schema
through initialization and arbitrary source `Steps`, including external input,
resumption cloning, and cleanup. This is an inductive environment component;
it does not establish full frame or heap compatibility.
`SourceOperandStructure`, `SourceOperandEffects`, and `SourceOperandExecution`
prove that partial operand frames form a contiguous stack prefix, with only
primitive evaluation above a pending term, throughout initialized source
execution. Captured continuations contain no partial operand frames, including
after cloning, activation, and disposal.
`SourceOperandSchemas`, `SourceOperandOutcomes`, and `SourceOperandTypes` connect
executing primitives and effectful terms to their source declarations with the
actual operand schemas throughout initialized `Steps`, including external
responses and cancellation. Primitive value preservation derives its instruction
admission from this invariant, including the pop operations' resizable-input
requirement. It still consumes the predecessor's finite value typing component.
`SourceFailureSchemas`, `SourceFailureEffects`, and `SourceFailureExecution`
prove that primary failures, accumulated cleanup failures, and failed obligation
records retain the source module's failure schema through initialized execution.
This includes failure data in captured continuations and its preservation under
renaming, resumption, disposal, and cancellation. The unwind value-preservation
lemma derives failure schemas from this invariant; the cleanup information
constructor supplies its own payload size and text checks.
`SourceCancellation` and `SourceCancellationExecution` prove that internal
source transitions retain the machine's cancellation reason and that all actual
`Steps` preserve the first accepted reason. Initialized execution validates text
reasons as UTF-8. Separately, decoding a reason through the wire codec establishes
its length bound, which is preserved by internal transitions and subsequent
cancellation inputs satisfying that same bound.
`SourceClosureContracts`, `SourceClosureEffects`, and `SourceClosureExecution`
prove closure compatibility throughout initialized source execution. Every stored
closure retains its admitted function and exact ordered capture binders, including
copies made through reusable capture activation. The reachable-closure theorem
combines this with lexical value-schema preservation to derive the function's
parameter, result, effect, and region contract and each captured value's membership
in the declared capture bound. The reference-safety theorem above supplies
reference liveness; full heap well-formedness remains a separate obligation.
`SourceCellStorage`, `SourceCellEffects`, and `SourceCellExecution` prove that
existing source cells retain their physical node, logical identity, region,
declared schema, and content schema through every actual transition.
`SourceCellIdentityExecution` proves that distinct mutable cell nodes also keep
distinct logical identities throughout initialized source execution. The clone
proof uses the actual copied-node order and fresh cell-identity map; aliases to
one physical cell remain permitted. The theorem covers all internal and external
steps, including cancellation, cleanup, disposal, and reusable activation.
`SourceRegionIdentityExecution` proves the corresponding uniqueness of logical
region identities among source region objects. Actual region creation and every
object copied during reusable capture activation preserve it; aliases to a
single region object remain permitted.
`SourceLexicalExecution` proves source-code bounds and lexical binding availability
through every initialized internal and external transition. Saved continuations,
including dormant and cloned captures, retain the bindings their continuation
code requires after capture trimming and renaming. Reachable variable evaluation
cannot fail with a missing-reference error. These results concern lookup
availability; complete typing, custody, borrowing, and progress remain separate
obligations.
`SourceScopeTreeExecution` proves that lexical parent records form an acyclic
forest throughout initialized source execution. Every allocated scope reaches
an actual parentless record. The proof follows scope creation and the actual
fresh map used for copied scopes, including dormant templates; it does not
assume parent IDs precede child IDs after cloning. Scope ownership and complete
frame compatibility remain separate obligations.
`SourceFrozenCells`, `SourceFrozenClone`, and `SourceFrozenStorage` connect saved
local contents to those cells, including nested dormant templates and every
object copied by the actual capture instantiator. `SourceObjectSchemas` and the
`SourceObjectStorage`/`SourceObjectEffects`/`SourceObjectExecution` induction
establish both frozen-cell compatibility and stored-object schema contracts
from successful initialization alone. Cells, packages, resources, resumptions,
borrows, regions, and capabilities retain their constructor-specific catalog
contracts. Closure contracts are supplied by the separate closure theorem above.
Reference liveness follows from `SourceReferenceSafetyExecution`. Full heap
compatibility and complete source-state well-formedness remain open.

The separate raw byte codecs in `Wire`, `ProfileCodec`, and `Images` check
complete BPI2, PST2, and protocol record framing, minimal integers, lengths,
section layout, numeric bounds, and input exhaustion. Their round-trip and
uniqueness theorems concern raw records; program-relative semantic admission
remains separate. `ValueCodec` proves exact prefix decoding,
completeness for every finite admitted value tree, and uniqueness of the meaning
of admitted external bytes. Recursive schemas and zero-width aggregates are
included. Its explicit syntax-depth limit belongs to witness generation.

`SHA256` gives a pure, total FIPS 180-4 definition, with kernel-checked empty,
`abc`, and two-block vectors and exact padding/block-length laws.
`ProtocolIdentity` defines the production domain prefixes and length-prefixed
preimages for program, request, residual-contract, and continuation identities.
Digest equality is not an injectivity or collision-resistance assumption.
`ProtocolCodec` adds PKI2 control admission and PKO2 reason/cleanup-failure
admission, with exact byte exhaustion and round-trip guarantees.
`SchemaAdmission` computes productive widths by a decreasing finite fixed point;
`SchemaEquivalence` computes the greatest closed relation on recursive type
pairs. `SchemaBisimulation` and `SchemaClasses` prove coinduction, equivalence,
and preservation of complete type shapes by the chosen representatives.
`SchemaDescriptor` implements quotient traversal and canonical descriptor
admission. Its decoder proves exact bytes, root zero, and a canonical fixed
point; general canonicalization idempotence and relocation laws remain open.
`ProtocolAdmission` proves soundness and completeness for request/result checks
against finite value witnesses, including exact descriptor and value bytes and
every digest binding. The witnesses are rechecked data, not trusted values.
Program-relative request provenance remains a separate runtime obligation.
The native protocol conformance gate executes 326 cases, all 21 schema tags,
all eight request preimage fields, and all nine program sections, including
154 expected semantic rejections and 82 malformed frames. These tests do not
establish runtime or program certification.

`InstructionAdmission`, `ProgramDeclarations`, `TerminatorAdmission`,
`RegionAdmission`, and `UseAdmission` check program declarations, earlier-slot
typing, exact authored-fault interfaces, continuation edges, higher-order
contracts, effect discharge, lexical region dependencies, consumption, and
capture bounds. The target conformance runner applies these checks to all 37
emitted programs before executing their 122 scenarios. Kernel proofs cover
defined operands, exact fault/constant bindings, constructor interfaces,
continuation arguments, exclusion of repeated noncopy consumption, and exact
finite effect/region dependency analysis. `BorrowPaths`, `BorrowMapping`, and
`BorrowGraph` define selectors, scoped input mapping, and reverse dependency
transfer. `BorrowSources`, `BorrowQueries`, and `BorrowRequirements` check finite
borrow-analysis tables by rederiving trace closure, dependencies through calls,
ownership constraints, and exclusion of fresh references from scoped results.
Their theorems establish local closure relative to the supplied summaries and
the checked scoped-result condition; the connection to runtime scope preservation
remains open. `check-v2-program-admission` compares 54 compiled programs with
native admission, covers all 48 opcodes, rejects 150 instruction/entry mutations,
and rechecks native borrow-analysis witnesses. It also retains 12 rejected
younger-reference source cases and mutates required witness data.

`ProgramReferences`, `ProgramCanonical`, `ProgramRemap`, `ProgramMapLaws`, and
`ProgramInterning` implement the root-ordered catalog traversal, stable textual
effect-row ordering, constant interning by schema and full bytes, and complete
record remapping. Kernel theorems establish numbering completeness, distinct
constant records, injectivity for retained nominal declarations, exact literal
interning, and preservation of operand, result-hole, capture and handled-effect
positions. `ProgramAdmission` combines declaration, control, use, region and
borrow checks with canonical numbering and the exact BPI2 decoder. Its
`decode_bpi2_sound`, `canonical_encode_decode`, and
`accepted_bytes_reencode_exactly` theorems bind the full image bytes and all
checked static conditions. Constant meanings and borrow summaries are finite
untrusted witnesses verified against that same program. Static admission is
distinct from historical reachability, machine preservation and source-to-target
equivalence; general program-normalization preservation remains open.
The program-admission gate also compares 55 complete canonical image round
trips and rejects 123 noncanonical programs that independently pass native
typing/ownership admission. It shifts and permutes all ten catalog kinds,
checks equal-name nominal effects, and compares complete normalized record bytes.

The independent target machine executes actual BPI2 blocks on the concrete
graph records, including higher-order control, regions/cells, resources,
ordered instruction faults, suspended cleanup, and cancellation. Stored blob
meanings carry proofs binding the complete raw bytes, and import preserves the
exact graph. `test/v2/target_machine.mjs` compiles the same 37 staged fixtures,
decodes their actual final images in Lean, and compares all 122 scenarios with
the source oracle. Constant, initial-argument, and response witnesses are
checked against their exact bytes. Both machines also execute the two raw
instruction probes. These are differential checks, not program certificates.
The clone implementation has kernel-checked dormant-template, cell, and alias
cases, plus general laws for its concrete renaming's fresh intervals,
restricted injectivity, outside identity preservation, and reference coverage.
Target polling, rejection, and finite trace composition have separate proofs.
Full graph admission, transition preservation, source/target simulation, and
runtime-segment certification are not established by these checks.

`Snapshot` implements the production preorder graph traversal, removal of
unreachable records, ordinal node renaming, and interning by complete blob
schema and bytes. Traversal terminates by a lexicographic measure over the
finite unvisited-node inventory and pending references, including graph cycles.
`GraphReferences` proves coverage of the ownership model's physical fields and
preservation of the complete ordered node/blob reference list under remapping.
`SnapshotReachability` and `SnapshotCollection` prove that discovery contains
exactly the reachable nodes, distinct nodes retain distinct IDs, materialization
reindexes every retained record, reachable paths are preserved, and the result
has no garbage or dangling references. Normalization succeeds exactly when
all reachable references are valid. PST2 admission proves input exhaustion,
exact bytes, and equality to the graph's canonicalization. `GraphRemapping`,
`SnapshotRelocation`, and `SnapshotCanonical` prove complete-record remapping
congruence and composition, traversal relocation, general canonicalization
idempotence, canonical byte equality under live-node and blob relocation, and
decoding of every width-valid canonical result. Relocation preserves root roles,
status, program identity, distinct live-node identities, and complete blob
contents; unreachable storage may differ arbitrarily.
`SnapshotCertificate` checks finite live-reference support and complete remapped
records, then proves equality to the original canonicalizer. The converse theorem
shows that every successful canonicalization has such support, including cycles,
shared nodes, and coalesced immutable blobs.
`check-v2-snapshots` compares 40 base graphs and their valid relocation/garbage
variants with the production Zig codec, exhausts all 24 native node tags, and
checks two malformed frames. Kernel-checked
examples distinguish cycle aliases, equal-but-distinct nodes, blob identity,
garbage rejection, and dangling references. These graph codec proofs do not
establish program-relative typing, custody, scope, or machine-step preservation.

`GraphAdmission` adds program-relative saved-state admission. Its checked
predicates cover the four state statuses, physical custody, frame and region
ancestry, exact scalar/blob values, every record interface, suspended captures,
effect origins, immutable holder graphs, cleanup records, and future borrowed
value demands at saved return slots. Finite projection witnesses must include
every successor task and every projected value or scope; their soundness theorem
prevents omitted dependencies from establishing admission. `TargetImage`
constructs machine contexts from the exact admitted BPI2 bytes and derives the
program digest. `CertifiedState.decode_sound` connects exact canonical PST2
bytes to those graph predicates and that admitted image. These results establish
structural admission; transition preservation and historical reachability remain
separate obligations.

The native graph conformance tooling collected 28,665 `advance` invocations
from all 122 source regression scenarios and 12 older-reference return cases.
All 28,531 resulting snapshots passed full admission with 56,175 closed
projections; 70 missing-row and 17 missing-output mutations rejected. Twelve
additional forged states retain valid current types, custody, capture, effect,
and direct-scope checks but violate a future borrowed-value lifetime. Both the
Lean checker and native state admission reject those states with rebuilt
projection witnesses. Native execution and native compilation of the Lean test
runner are conformance evidence, not per-artifact kernel proofs.

`TargetBoundary`, `TargetInvocation`, and `TargetRun` define public preparation,
restoration, response/cancellation handling, exact `advance` quanta, and finite
`run` paths ending at the first terminal, parked, or yielded boundary. Internal
path lengths are untrusted certificate data: an incomplete path or a step after
the stopping boundary rejects. `TargetExecution.checkInvocation_sound` binds
every PKI2/PKO2 byte to those transitions and their derived semantic events.
`segment_composition` requires each successor to consume the exact preceding
PST2 bytes and proof-only request clock. Completed initial-execution claims
require nonempty records and a terminal final outcome. Arbitrary imported
states receive admission without a claim of historical reachability.

`tools/v2/execution_producer.lean` emits numeric-data proof modules; execution
and analysis results produced by its compiled code remain untrusted candidates.
Each certificate proves static image admission, exact encoding, complete public
records, and the actual target execution using ordinary kernel proofs.
Executions sharing an image share its checked admission package. Borrow and
canonical-order calculations use checked local facts and general composition
proofs; every generated dependency is inventoried, audited, and replayed.
`SHA256Certificate` checks every witnessed compression and complete message
exhaustion, then proves equality to `SHA256.hash`. It assumes no digest
injectivity. Large messages use separately checked compression steps and a
proved block-chain composition law. Trait search stops at an unchanged support; a general theorem
proves equality to the previous bounded expansion.
Hash rewrite keys use natural-number byte values, with a general round-trip
proof, so computed bytes and byte literals select the same proved fact.
Schema-width witnesses similarly check each actual refinement round and use
the existing fixed-point theorems; computed widths are never assumed.
`ExecutionEvaluation` composes checked internal fragments with the original
evaluator's final stopping check. Its descriptor lemma proves that an admitted
external childless schema has its exact one-node canonical descriptor, avoiding
repeated whole-program equivalence calculations for scalar requests.
Long executions use checked heap appends and lookups where applicable, with
proof fragments split across inventoried modules to bound elaborator memory.
Other long traces name identical complete heap-node literals once and split
every eight proof fragments. Mutable nodes with different contents receive
different definitions; node IDs never serve as the sharing key.
The complete invocation and stopping boundary remain part of the final claim.
`ExecutionCertificate` provides preparation composition laws for saved-state
continuation, response, and cancellation. The plain run emitter uses these laws
and `SnapshotCertificate` to check preparation and normalization in separate
modules without changing the invocation checker or its exact byte subjects.
`TargetStorageLaws` proves that every externally admitted value can pass through
the target's actual store/load path without changing its meaning. This includes
fixed-width scalar padding, recursive aggregate blobs, and exact blob interning.

`test/v2/execution_artifacts.mjs` freezes captured images, invocation records,
and borrow witnesses, generates certificates, checks their complete claim
types and subjects, audits logical dependencies, and runs fresh replay. It
also rejects a theorem of `True` and changed image/input/output subjects before
restoring and replaying the clean proof. The lexical, deep-handler, and
three-record generator executions have passed kernel, trust, fresh replay,
and altered-subject controls. This does
not yet provide full fixture coverage or source/runtime certificate composition.
The three-record `operand-failure-5` execution now passes ordinary kernel
checking with composed internal fragments and checked descriptor evaluation.
The actual producer's 20,003-step recursive certificate also passes ordinary
kernel checking with shared state facts. Candidate generation covers all 134
cases and 308 records, but the full cohort's kernel, trust, and replay gate
remains incomplete. The complete cohort must pass before full runtime coverage
is claimed.

The invocation conformance cohort compares all 28,665 native `advance` records
and 308 native `run` records from 134 cases against the formal target boundary.
Separate captures compare complete WASM records and alternating native/WASM
restoration. The native adapter checks that invocation preserves its input
buffer, and the alternating collector executes a frozen adapter copy. These
larger cohorts remain differential conformance rather than kernel certificates
for every recorded execution. General collection/transition preservation and
source-level composition remain open.

`TargetRejection` proves refusal uniformly over every admitted image
interpretation and every invocation witness. This prevents a deliberately bad
witness from manufacturing a rejection. Its checker covers malformed input or
saved-state records, image/state identity mismatches, missing pending requests,
and wrong response bindings. Certified refusal also requires an admitted image,
an error status, complete diagnostic bytes, empty output, and unchanged input.
Ten actual native/WASM refusal records have per-record kernel proofs, exact
claim-type checking, logical trust audits, and fresh replay. Altered image,
input, output, diagnostics, input-after bytes, status, backend, and a theorem of
`True` are rejected. The indexed refusal proposition retains the complete
record in its type, including fields whose validity can reduce to `True`.

`TargetCapacity` retains every capacity byte and the actual completed retry
sequence, including guest input-after buffers and prepare/execute statuses.
It derives no-commit and unchanged-input properties and requires an ordinary
completed execution certificate for the retry and its continuation. Allocation
quantities remain measured fields, without a formal allocation-bound claim.
All three arena captures have passed per-record kernel checking, exact claim
checking, trust auditing, and fresh replay, followed by 19 altered-subject
controls and a restored clean replay. The executable conformance checker also
rejects 48 mutations, including missing completion records.

From this directory, `lake exe boundary-certify --image FILE --execution FILE
--witness FILE --output FILE` certifies a complete initial execution using the
pinned tools. The result records complete subject identities, checked theorem
and dependency-file hashes, trust results, and fresh replay. Exit codes are
`0` for certification, `1` for rejection, `2` for inconclusive, and `64` for
invalid usage. Output replacement preserves input hardlinks and invalidates an
old success before rechecking. `--source FILE` in place of `--execution FILE`
currently returns inconclusive because full-profile translation rules are
unfinished; it cannot report a fragment proof as a program certificate.

| Evidence tier | Current boundary |
| --- | --- |
| Model theorem | The explicitly named Lean definitions and premises above. |
| Program artifact | Restricted byte-bound projection/constant and lexical-closure proofs for all admitted `u64` arguments, including lexical overflow. Full specified program certification remains unimplemented. |
| Runtime segment | Exact initial-execution claims for lexical, deep-handler, and generator records; ten native/WASM refusal claims; three arena-capacity and completed-retry claims. Full runtime scenario certification and source-level composition remain incomplete. |
| Differential conformance | Independent source-oracle and native/WASM executed cases; no universal claim. |

The complete proof-closure specification remains **incomplete**. Outstanding
work includes full source ownership admission and machine `WellFormed` preservation;
target transition preservation; general proofs for failing operands,
ownership graphs, borrowing, cleanup, and capture instantiation;
remaining protocol rejection coverage; divergence-sensitive
translation across every production pass and construct; complete runtime scenario
certification and source composition; and the complete program CLI/result record
and aggregate certification targets. The implemented gates must not be reported
as completing those obligations.

`tools/v2/linux-proof-tools.sh` acquires Linux x86-64 Lean, Zig, and Node archives
under exact SHA-256 pins. It requires standard download/archive utilities and
works without nested Docker. With its printed `proof_tool_bin` on `PATH`, run
`sh tools/v2/check-linux-formal.sh`. The runner executes the implemented aggregate,
including formal mutations and restricted artifact proofs; it is not the completed
full-profile acceptance gate. Compiler/data consumers do not invoke it.
