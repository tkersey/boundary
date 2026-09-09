# Checked core and its current proof boundary

This is a model of Boundary control and lowering, checked with the pinned
Lean 4.33.1 toolchain and bundled Std. It has no external package dependencies.
Run `node check.mjs` in this directory, or use `zig build check-v2-semantics`
from the repository. The gate discovers and builds every module under
`BoundaryV2/`, rejects build warnings, and enforces the axiom policy below.
`node check.mjs --self-test` also exercises the gate with isolated mutations;
Linux CI runs those mutations and the repository aggregate. `lake build` remains
useful for proof development, but alone does not run the trust gate. Importing
Boundary's Zig modules does not execute these commands or require Lean.

The artifacts under proof are the Lean definitions here. The production Zig
compiler and World interpreter are not Lean programs and do not have a checked
refinement link to this model. Their correspondence is tested separately by the
independent source oracle and cross-runtime conformance.

| File | Checked claims |
| --- | --- |
| Lowering.lean | Typed lexical expressions with Unit, Boolean, mathematical Nat, products, de Bruijn variables, and bind compile to explicit first-order instruction lists. `compile_preserves_value_and_scope` proves result equality, unchanged caller environment, and unchanged operand-stack tail for every expression, environment, and stack. |
| Control.lean | Typed context composition; selection by explicit attachment identity; exact reconstruction of both sides of a selected delimiter; deep/shallow capture; no second return-clause application to clause answers; preservation of non-tail postprocessing; operation progress to a selected delimiter or a residual operation. |
| ControlLowering.lean | An independently defined stack of first-order blocks preserves source context values, composition, attachment selection, and deep/shallow capture. `compilation_preserves_non_tail_resume` combines these properties. `return_step_simulation` and `return_trace_simulation` relate each return transition and any finite sequence of such transitions. |
| Ownership.lean | Fresh/live/spent token invariants; consumption preserves disjoint unique ownership; a consumed token cannot resume again; multi activations obtain distinct control identities; lexical region entry and checked exit preserve scope. |
| Regions.lean | Immutable local-cell templates; consistently renamed local references; reads from current outer storage; alias and scope preservation; distinct names under disjoint fresh maps; multi activation preserves scope and ownership; freezing consumes the original token. |
| Effects.lean | A complete finite effectful machine: effects on either side of bind, branches, explicit capability environments, nested deep/shallow handlers, non-tail clause callers, immutable multi templates, region reads/writes, and residual resume/dispose/transfer. `machine_progress`, `tick_preserves_invariants`, and `transition_preserves_invariants` cover every control constructor. |
| EffectsLowering.lean | All embedded lexical expressions compile into first-order instruction blocks, including expressions in dormant nested templates. `effectful_step_simulation` and `effectful_trace_simulation` preserve transitions and finite state-observation samples (including repeated parked observations). `drive_preserves_invariants` extends ownership preservation to any accepted external script. |
| EffectsIdentity.lean | Selection reconstructs the actual effectful stack, uses the requested identity, and stops at its nearest delimiter. Initialization reserves above ambient capabilities. Internal and accepted external transitions preserve the attachment supply bound through active stacks and dormant templates. Local renaming is injective on the old bounded identity domain and successive allocation intervals are disjoint. |
| EffectsTrace.lean | `driveEvents` records newly exposed events rather than polling samples. Arbitrarily many parked internal polls are silent. Compilation preserves these event traces, while accepted scripts preserve both custody and attachment bounds. The original sampling API is unchanged. |
| EffectsChecks.lean | Kernel-checked regressions distinguish ambient capabilities from newly installed handlers, exercise dormant aliases and successive activation intervals, retain separate requests with equal payloads, and emit disposal/transfer only once. Source and compiled executions agree. |
| EffectsExamples.lean | Kernel reductions establish deep/non-tail result 114, shallow/non-tail result 104, direct operation-clause answer 7, the two State/Choice results `(1,1)` and `(1,2)`, effectful binds across two residual responses, and consumed sender custody on disposal/transfer. Compiled examples independently reduce to the same expected values. |

The planned formal-core inventory is covered by the following construction and
theorems. Type and scope preservation are intrinsic: `Flow` indexes lexical
variables, capability evidence, region count, and result type; each `Position`
contains a heap with exactly its indexed region count and a typed stack to the
same root scope/result. A cell reference is a `Fin` index into that heap.
`tick` is total over this complete typed control state. There is no stuck or
unchecked-cast alternative. The additional `Machine.Valid` predicate requires
unique, disjoint live/spent token sets and exact custody: the pending position
owns the sole live token, and every other state owns none.

`Machine.AttachmentsBounded` is a separate invariant: the next attachment supply
is strictly above all reachable attachment identities, including saved capability
environments and dormant nested templates. `initial` derives this bound from the
ambient capabilities, treating the requested supply as a lower bound. An already
sufficient supply is unchanged. Every internal transition and accepted external
action preserves the bound. It is not a complete graph-admission predicate and
does not assert uniqueness of every simultaneously active delimiter.

| Required formal observation | Evidence |
| --- | --- |
| Type, scope, and linear-ownership preservation | Indexed `tick`/`transition` results; `tick_preserves_invariants`, `transition_preserves_invariants`, and `drive_preserves_invariants`. |
| Progress up to residual effects | `machine_progress`; `live_residual_progress` proves each typed residual disposition has a valid successor. |
| Simulation into first-order code | `compile_preserves_value_and_scope`, `effectful_step_simulation`, `effectful_trace_simulation` (samples), and `effectful_event_trace_simulation` (events). |
| Attachment allocation | `initial_reserves_attachments`, `tick_preserves_attachment_bound`, `transition_preserves_attachment_bound`, and `drive_preserves_attachment_bound`; compilation preserves the invariant. |
| Return, bind, deep/shallow handling, non-tail resume | Every corresponding `Flow`/`Frame` constructor participates in the global step/trace proofs; closed examples distinguish the return-clause and non-tail rules. |
| Regions and linear/multi disposition | `LocalHeap` stores only the captured prefix; `rebasing_preserves_current_outer_heap`; exact one-shot custody and `residual_disposition_consumes_once`; multi activation and nested template remapping are covered by the global simulation. |

The effectful core uses one mathematical `Nat -> Nat` operation family with
arbitrarily many explicit instances. Its bind bodies can perform effects.
Handler return clauses and clause postprocessors are pure; clause plans dispose,
resume once, or fold a finite list of reusable resumptions. The control algebra
is shared by the source and target instantiations. Compilation replaces every
source expression with typed instruction data; it does not claim a separately
derived production interpreter or flatten the whole model into BPI2 blocks.
The checked attachment bounds and finite-renaming laws apply to this model's
allocator, not to World's production allocator or a serialized graph's complete
admission rules. The effectful simulation still shares its control algebra;
there is no checked translation into actual BPI2 control-flow blocks.

The separate `Regions.lean` model uses number-valued cells and explicit local/outer references.
Fresh-name injectivity and disjointness are hypotheses of the corresponding
renaming theorems. No theorem silently assumes those properties of an arbitrary
allocator. The clone-safe modeled template types have no exclusive resources or
exit obligations. The ownership ledger models logical custody, not serialized
allocation history or the entire portable ownership graph. Transfer consumes
the sender's custody; an independent receiver graph is outside this model.

Fixed-width arithmetic faults, recursive application code, arbitrary effectful
operation clauses, first-class suspension packages, scoped forwarding,
cleanup/cancellation, graph cycles, canonical wire formats, garbage collection,
and selective compiler optimizations have separate executable evidence and are
outside this formal core. Finite script lengths in `drive`, `driveEvents`, and
the closed-example `ticks` helper are observation horizons; no machine transition
reads semantic fuel.

## Samples and events

`drive` retains its original contract: it samples `observe` after each accepted
input. Polling a pending or terminal machine therefore repeats that observation.
`driveEvents` instead records an observation when an internal transition from a
running machine exposes it, or when a pending request is disposed or transferred.
Internal polls of a parked machine emit nothing. It does not deduplicate by
payload: two distinct requests with equal identity and payload remain two events.
Both drivers exclude an implicit initial observation; use `observe` to inspect a
state before supplying inputs. Invalid external actions still reject.

## Enforced trust policy

`Trust.lean` examines transitive axiom dependencies of every declaration owned
by a `BoundaryV2` module, including private helpers, definitions, and unused
axioms outside the `BoundaryV2` namespace. Only `propext`, `Quot.sound`, and
`Classical.choice` are permitted. An unexpected dependency is a build error,
not merely a printed report. Declaration/theorem counts include Lean-generated
helpers and are not counts of handwritten claims.

`check.mjs` discovers modules from the source directory and imports them into a
temporary audit, so a new file omitted from `BoundaryV2.lean` cannot escape the
gate. `--self-test` checks a clean orphan module and rejects a private `sorry`,
an unused custom axiom, a definition using `sorry`, and a `native_decide` proof.
These probes use isolated temporary copies. Their build warnings are allowed
only so the tests verify rejection by the axiom policy itself; ordinary builds
reject warnings. No test mutates the working tree.

There are no custom admitted axioms, unfinished proof placeholders, native
decision shortcuts, unsafe definitions, or partial definitions in the formal
core. The kernel and standard logical axioms are its logical trust boundary.
The audit is build tooling, not an additional axiom or a proof of the Zig compiler.
