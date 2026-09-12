# Generalized effects proof core

This replaces the full-profile proof-closure and production-certification project.
The accepted specification is **Boundary — Generalized Effects Proof Core**,
version 1.0, September 12, 2026. The five claims below are the required exported
statements; this contract does not assert that their implementations exist yet.

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
enclosing owner and cannot escape through an owned shorter-lived package;
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
| Unmodified World dependency | `5175e775005ee95e141b079936be163e1e75b803` | Pinned conformance consumer; no changes required. |
| Boundary #147 | `b6e74aec0664652b89e75ea38db8436c5e8b3fc8` | Donor for trust, selection, freshness, events, and Linux CI. |
| Boundary #148 | `ce680c7846a2a9cd7dc10389e94f417900250b37` | Donor for relevant local ownership/exit laws and concrete regressions. |

Preserve both donor branches and unfinished work. Neither PR is merged intact.
After the replacement PR has a durable link, document supersession and close the
donors without merging. Do not merge the replacement or publish a release.
