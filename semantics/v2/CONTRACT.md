# Generalized effects proof core

This replaces the full-profile proof-closure and production-certification project.
The accepted specification is **Boundary — Generalized Effects Proof Core**,
version 1.0, September 12, 2026. The five claims below are the required exported
statements. [GeneralizedContracts.lean](BoundaryV2/GeneralizedContracts.lean)
now declares the five names as proposition-valued contract structures. No
inhabitants of those structures are exported. Their present fields expose the
stateful observation and local construction obligations; registry/exit execution
coverage and the remaining compositional obligations below are still required.
The [current proof inventory](README.md) gives the checked components and gaps.

The proof subject is a typed symbolic calculus and its independently defined,
first-order control representation. The production compiler and pinned World
are checked by ordinary conformance tests. This work produces no program,
execution, byte-format, refusal, or capacity certificates.

## Common domain and assumptions

- An arbitrary typed operation signature supplies payload, result, and scoped
  computation-argument types. Nominal attachment identity is separate from that
  signature. Return and operation clauses are ordinary effectful computations.
- A leaf algebra supplies typed data and pure value-or-authored-fault outcomes.
  It preserves the declared ordered support and cannot perform control effects,
  transfer ownership, or close a scope. Products, sums, environments, owned
  continuations, and borrowed references have explicit structural support.
- Core terms are intrinsically typed. Local operations take their actual use,
  capture, and finite-scope permissions. No premise assumes the translation,
  handler interpretation, cloning algorithm, or production verifier is correct.
- Typed registry lookup uses decidable equality of data/effect indices, a pure
  interface operation. The core implements structural type comparison. One
  registry can contain continuations with different input and answer types.
- Source evaluation and target dispatch are independent. Target closures and
  suspended futures contain inspectable code identities and environment/frame
  data, never callbacks or instructions to execute the source evaluator.
- Finite recursive code tables and arbitrary finite evaluation derivations are
  admitted. Test horizons are not semantic fuel. Silent target administration
  must drain by a proved local measure or be covered by positive step matching.

## Required exported claim statements

### D — `Generalized.Defunctionalization.adequacy`

For every signature, lawful leaf algebra, typed core term, related source/target
initial environments, and finite source observation derivation, the total core
translation has a corresponding target derivation; conversely every finite
observation of the translated target has a source derivation. Related observations
distinguish return, authored failure, yield, and open request. Open requests relate
their typed scoped bodies and suspended futures under every related accepted
response, not only their current payload or eventual result.

Derive this statement from closure application, exact captured-environment order,
code/body identity, caller preservation, argument/result positions, context
composition, call/unfold, and handler-context laws. It is not a theorem about
final BPI2 bytes or a condition on an opaque compiler.

### H — `Generalized.Handlers.interpretation`

For every typed signature, effectful handler, and enclosing typed context,
selection reconstructs both sides of the nearest matching nominal attachment;
nonmatching handlers forward with scoped bodies intact. Installation reserves
fresh identities. Deep/shallow capture, successor handlers, use-site injection,
answer transformation, clause-answer bypass, and non-tail resumption preserve
the authored interpretation and its open future. The translated interpretation
composes under an arbitrary enclosing core handler.

### U — `Generalized.UseScope.preservation`

Every admitted local creation, move, consumption, package/unpackage, disposal,
and reusable activation preserves the relation between the core's physical
owning occurrences and its custody operations. Count occurrences with
multiplicity. One-shot authority is consumed before entry; affine disposal and
linear use retain their distinct permissions. Clone-safe activation establishes
fresh local maps, preserves all aliases and dormant support, separates branch
state, and reads current shared outer state. Borrowed support retains a live
enclosing owner and cannot escape into an owned package that outlives its dependency;
abstract-resource authority remains nominal.

This is a local core construction/transition claim, not complete production
borrow inference or heap preservation.

### X — `Generalized.Exits.composition`

For every finite composition of admitted core operand, capture, attachment,
cleanup, and exit transitions, evaluated operands retain evaluating custody
until handoff; later failure transfers the outstanding work once in its declared
order. Inner scopes precede outer scopes, with creation order within a scope.
Each pending cleanup has one initiation right, and a running cleanup retains
its continuation through capture and suspension. Normal completion, failure,
abandonment, and cancellation preserve their distinct precedence and ordered
failures; the first cancellation is retained and repeated cancellation cannot
restart cleanup. No termination or physical exactly-once guarantee is assumed.

### O — `Generalized.OpenControl.observation_relocation`

For every typed pending core future, polling and rejected/mismatched responses
preserve it without opening a request or consuming authority. Accepted typed
responses reenter the matching interpretation. Equal requests at different
logical occurrences remain distinct. Every consistent injective relocation of
the admitted finite support commutes with the core control/capture operations,
preserving aliases, ownership, obligations, and explicitly external identities.
This is logical relocation, not a codec, hash-injectivity, or anti-replay theorem.

## Production evidence and exclusions

`GeneralizedStateObservations` takes finite closures of the existing independent,
permission-sensitive source and target execution relations. Every observation
retains the current heap, cells, live regions, and typed future. Initialization
and response entry are proved structurally. `GeneralizedStateSimulation` now
proves preservation for every constructor of the current stateful relation and
lifts it over arbitrary finite derivations to all four observations. That proof
supplies D's preservation field; initialization and response fields also have
checked defaults. `GeneralizedStateReflection` proves the reverse operand-prefix
law for every computation constructor, recovering actual source evaluations,
capture partitions, owning state, and a finite residual target run. Authored
return expressions have full finite observation reflection, including owned
closure construction and later operand failure. Reflection through the remaining
receiving instructions and arbitrary contexts now composes in
`GeneralizedFiniteReflection`. `stateful_observation_reflected` supplies D's
reflection field for the current execution relation, with actual source steps,
current resources, and all four observation forms. Handled requests use the
source selector across their saved and surrounding contexts; the old syntactic
handler rule is a derived case. The source and target selectors remain independent.

`GeneralizedRegisteredExecution` embeds core steps, clone registration, and all
three multi-use entries into one retained runtime. Each core successor writes
its current cells and live regions back into that runtime. Registry, dormant,
and active support participate in its ordinary allocation and operand rules.
The source and target support collectors agree. The former `ResumeRun` and
`CloneEntry`/`CloneResult` drivers have been removed; their correspondence and
distinguishing regressions now use this relation. Clone correspondence includes
registration and a positive drain back to the actual caller.

D explicitly requires preservation and reflection of these registered finite
observations, with related registry/arena state and all four observation forms.
Registered initialization, response entry, and both finite observation
directions are proved. `GeneralizedRegisteredSimulation` derives every registered source
step from the existing core, resume/injection/successor, and clone laws, then
composes arbitrary finite derivations. Core preservation now accepts retained
support. Clone correspondence accepts actual related target heaps with
noncanonical administrative frames and keeps unrelated controls intact.
The source context's existing authored fields provide a checked left inverse
for capture descriptions; bare callback equality supplies no provenance.

`GeneralizedRegisteredReflection` supplies the converse from arbitrary finite
target derivations. Core and registered drivers use one operand-reflection
argument, instantiated by proved local target-step laws. Shared receiver
inverses and the registered clone/multi-entry inverses recover actual source
steps, then compose through enclosing contexts and all four observations.
Source heap descriptions project back to the actual heap under the structural
relation; operand evaluation preserves that projection and its ownership.

Disposal and exit/lifetime composition remain unfinished. The registered
driver still lacks those transitions, so this correspondence does not yet
establish the complete D/H/U/X/O milestone.

The source now defines cleanup entry and completion independently through its
higher-order programs and contexts. D's `cleanup_preservation` and
`cleanup_observations` fields connect every currently implemented source cleanup
step and arbitrary finite derivations to the shared target frame driver. The
proof retains current resources, owned saved results, all four observations,
and related suspended futures. Local finalization admission also reflects from
target to source. Source value and control disposal now join that relation:
actual fields and grants govern structural disposal, and source cleanup executes
inside disposed continuations. D's `value_disposal_preservation` and
`control_disposal_preservation` fields cover arbitrary finite derivations of
these operations. Running, parked, and captured cancellation now preserves the actual
source future and first reason; D also exposes its source/target admission
correspondence. Yield parking, continuation, capture, and reattachment compose
through the same finite exit simulation. Source unwinding-region disposal now
uses current cells and retained outside roots inside that mutual relation.
D's `region_disposal_preservation` and `authored_disposal_preservation` fields
connect arbitrary finite region work and authored disposal to their existing
target operations. The authored operation keeps its caller distinct and returns
to its ordinary computation after yielding cleanup and actual authority consumption.
Checked normal-region retirement now also participates in the finite exit
simulation, preserving the actual returned value, current storage, and diagnostics.
It uses the existing permission that retiring cells are unowned and surviving
results/contexts contain no retiring storage aliases. This is separate from
transferring a live scope to an escaping owned package. Scope/lifetime transfer,
suspended-work abandonment, the join with registered execution, and reverse
finite exit correspondence remain required before complete adequacy can be claimed.

X now includes checked local fields for frame completion, region handoff,
retained roots, and finite frame/control/value embeddings. Authored disposal
executes the same handler-aware frame transitions as cleanup. Its caller remains
separate from the abandoned future; normal and abrupt cleanup completion use
current resources and preserve the actual saved body value. Returned handler
answers go through value disposal before the disposal caller receives unit.
The separate nested-disposal states and old unwind wrapper have been removed.
Pending values and their grants remain retained through intermediate frame
states. Standalone capture/abandonment laws still support the unfinished local
registry/lifetime and suspended-work connections; those connections and full
source/target exit observations remain required. No final contract inhabitant
is claimed.

`GeneralizedContractChecks` consumes the declared field types and checks the
stateful observation definitions. Its hypothetical contract arguments are
statement checks, not evidence that the contracts are inhabited. The existing
trust mutation suite rejects replacing each contract with `True`, replacing
the source stateful observation definition with the ordinary relation, and
replacing either source or target registered observations with core-only observations. This
gate also rejects omitting retained caller roots from nested region retirement
discarding source failure history/cancellation when cleanup begins, and forgetting
spent authority during source resource disposal. It
does not replace review of the complete types or completion of their proofs.

The conformance command must take an explicit unmodified World checkout/artifact,
compile ordinary public-builder programs through the normal pipeline, and compare
observations against the independent source/core meaning. Cover the specification's
lexical, signature, handler, scoped-body, ownership, branching-state, lifetime,
exit, cleanup, open-interaction, portability, and library-composition families.
Use a small reproducible generated sample where the existing harness permits it.
Preserve the existing data, source-oracle, authoring, economy, legacy, capacity,
input-buffer, and aggregate tests and consumer dependency isolation.

The excluded production operational replicas, scalar/codec/schema/hash theories,
certificate generators, witness emitters, and compiler evidence callbacks are
not prerequisites or promised follow-up features. Extract useful local laws and
independently justified regressions without their complete donor import closures.

## Baselines and donor disposition

Refreshed at implementation start:

| Role | Commit | Disposition |
|---|---|---|
| Boundary baseline | `55e8feedcae0b9ee1492da11f9fbd4a1ac7ff328` | Clean replacement starts here. |
| Unmodified World dependency | `87698f92ca7be4d5442e97ba27a2468aa3ff6a7c` | User-approved existing cleanup-disposal fix; no source changes. |
| Boundary #147 | `b6e74aec0664652b89e75ea38db8436c5e8b3fc8` | Donor for trust, selection, freshness, events, and Linux CI. |
| Boundary #148 | `ce680c7846a2a9cd7dc10389e94f417900250b37` | Donor for relevant local ownership/exit laws and concrete regressions. |

World main `5175e775005ee95e141b079936be163e1e75b803` was inspected at startup.
The retained cleanup-disposal regression fails there with `InvalidState`; the
existing fix above passed all 127 cases in native/WASM comparison and was
explicitly approved as the unmodified test dependency.

Preserve both donor branches and unfinished work. Neither PR is merged intact.
The replacement is draft PR #149. Both donors are closed as superseded without
merging; their branches/history and unfinished work are preserved. Do not merge
the replacement or publish a release.
