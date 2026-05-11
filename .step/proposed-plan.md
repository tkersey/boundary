Iteration: 3

# Typed Protocol Morphisms And Effect Reinterpretation

## Round Delta
- Converted the spec handoff into a dependency-ordered implementation campaign for local `main` at `32418797a54b753ff829c3b36432cb7218fe8b0b`.
- Locked one additional execution decision: add `Program.Morphism` as the static source-target witness so effect rows do not infer reinterpretation from handler bodies.
- No scope expansion: optional `effect_middleware` stays stretch; root/session/fingerprint constraints stay hard gates.

## Summary
Implement typed protocol morphisms by first adding protocol-level operation descriptors under `ability.ir.schema.Protocol`, then adding `Program.Morphism`, `Program.ProtocolRequest`, handler `reinterpret`, protocol-op handlers, composed interpreter execution, effect-row metadata, trace metadata, tests, docs, and `run-protocol-reinterpretation`. First wave is descriptor/ref/fingerprint groundwork; done means the required example, full Zig build/test/lint, focused reinterpret/morphism/effect-row/capsule/trace lanes, and existing example runners pass without public-root, `Program.Session`, `Program.run`, `ProgramValue`, request-token, or existing fingerprint-version drift.

Use `Program.Session` as the only continuation authority. A reinterpreted request is typed inspectable data plus an owned source capsule and mapper witness; it is not a runtime, durable id, token, pointer carrier, or persistence format.

## Iteration Change Log
- iteration=1 focus=baseline_decisions round_decision=continue delta_kind=material evidence=spec handoff plus repo no-hit for reinterpret/morphism what_we_did=converted requirements into API and execution sequence change=added Program.Morphism witness and descriptor-first sequencing sections_touched=Summary, Interfaces/Types/APIs Impacted, Data Flow, Decision Log, Implementation Brief
- iteration=2 focus=operability_risk round_decision=continue delta_kind=none evidence=adversarial pass found capsule-authority risk already covered by data-only request and rollback gates what_we_did=checked failure modes, rollback triggers, and mapper/descriptor typing change=no material delta sections_touched=Edge Cases/Failure Modes, Rollback/Abort Criteria, Adversarial Findings
- iteration=3 focus=verification_convergence round_decision=close delta_kind=none evidence=press pass checked Interfaces, Data Flow, Tests/Acceptance, and Rollback with no new errors what_we_did=closed with two clean rounds and machine-readable contract signals change=no material delta sections_touched=Convergence Evidence, Contract Signals, Implementation Brief

## Non-Goals/Out of Scope
- Do not change `Program.run` semantics or `Program.Session` primitive stepping semantics.
- Do not hide manual Session loops, remove Capsule APIs, remove `Program.protocol`, or make interpreters mandatory.
- Do not add async runtime, network/LLM integration, parser/compiler/source language, public VM APIs, Artifact APIs, persistence backend, cross-thread sessions, serializable request tokens, trace serialization requirements, public root widening, `ProgramValue` widening, or new value codecs.
- Do not delete lower-level examples: `continuation_branching`, `interpreter_branching`, `custom_approval_workflow`, or `agent_loop`.

## Scope Change Log
- scope_change=none; reason=plan consumes the accepted spec-pipeline scope without expansion or reduction; approved_by=user brief and spec handoff

## Interfaces/Types/APIs Impacted
- `ability.ir.schema.Protocol.operation(name, options)` and alias `op(name, options)`: returns a protocol-level descriptor with `kind=.protocol_operation`, `protocol_label`, `op_name`, `op_ordinal`, `op_mode`, `Payload`, `Resume`, `Result`, `payload_ref`, `resume_ref`, `result_ref`, `may_resume`, `may_return_now`, and deterministic `fingerprint`. `options.schema_refs` is required for product/sum refs; `options.Result` defaults to `void` and is used for choice/abort `returnNow` target responses.
- `Program.Morphism(.{ .source, .target, .Mapper })`: static witness tying a `Program.protocol` source operation site to a schema protocol target descriptor and mapper. Effect-row metadata reads this witness, not handler function bodies.
- `Program.ProtocolRequest(TargetOp)`: owned typed target request value with copied payload, source program/plan/site/request/capsule metadata, target protocol/op/ref metadata, target payload fingerprint, reinterpret fingerprint, and no durable request token or pointer/address fields.
- `Program.Handler.SourceOutcome(SourceSite)` and `Program.Handler.TargetResponse(TargetOp)`: typed outcome vocabularies used by mappers. Source outcomes are restricted by source-site mode; target responses are restricted by target-op mode.
- Handler API: add `control.reinterpret(TargetOp, payload, Mapper)` plus `Program.Handler.reinterpret(SourceSite, TargetOp, payload, Mapper)`; interpreter captures the current source capsule when applying the outcome.
- Protocol handler API: add `Program.Handler.protocolOperation(TargetOp, handler_fn)` for target protocol requests. Handler returns `TargetResponse(TargetOp)` through helpers such as `protocolResume`, `protocolReturnNow`, `protocolForward`, and `protocolFail`.
- Interpreter API: add `ExecutionResult.reinterpreted`, `Program.Interpreter.compose(.{ ... })`, `continueReinterpreted(...)`/`Reinterpreted.respond(...)` convenience for host-supplied target answers, and effect-row helpers `effectRow(Program)`, `assertEliminates(Program)`, `assertReinterprets(SourceSite, TargetOp)`, `assertHandlesProtocolOps(.{ ... })`, and `assertResidualSites(.{ ... })`.
- Trace API: add separate reinterpret trace/fingerprint metadata; do not mutate existing request/site/response/value/capsule fingerprint contents or version constants unless implementation proves their contents changed.

## Data Flow
1. `Program.Session` yields a source operation request for a static `Program.protocol` site.
2. A Program-site handler receives the typed request and `Control`, then returns `reinterpret` with target descriptor, target payload, and mapper witness.
3. Interpreter validates payload/ref/mapper shape, captures the current source continuation as `Program.Session.Capsule`, builds `Program.ProtocolRequest(TargetOp)`, records reinterpret trace metadata, and offers the target request to later composed interpreters.
4. If no protocol-op handler accepts the target request, Interpreter returns `.reinterpreted` containing source capsule, source trace/request/capsule fingerprints, target request, mapper identity/fingerprint when feasible, and stop reason.
5. If a protocol-op handler answers, Interpreter validates the target response, applies mapper to produce `SourceOutcome(SourceSite)`, restores the source capsule into a fresh Session, applies the source outcome to the restored request, and continues.
6. Manual host path remains available: host receives `.reinterpreted`, inspects target metadata/payload, supplies a typed target response through `Reinterpreted.respond(...)`, or restores the source capsule directly and applies the mapped source outcome through ordinary Session APIs.

## Edge Cases/Failure Modes
- Wrong target payload type: compile-fail through `control.reinterpret`/`Program.Morphism`; runtime fallback returns `ProgramContractViolation` only if dynamic data is malformed.
- Missing product/sum schema ref: compile-fail through `schema_refs`, matching existing schema.Protocol behavior.
- Mapper returns invalid source outcome: compile-fail when source mode proves impossible; runtime contract violation only for dynamic ref mismatch.
- Target choice/abort uses non-void terminal result without declaring `Result`: compile-fail or typed test failure at descriptor construction.
- Duplicate protocol-op handlers in a composition: fail closed at comptime; no priority ordering.
- Forwarded or unhandled target protocol request: return `.reinterpreted` with owned source capsule and target request intact.
- Restored source capsule produces fresh request tokens: tests must prove tokens are not reused while request/capsule fingerprints remain stable.
- Existing fingerprint churn: abort unless a changed hash input is intentional and documented.

## Tests/Acceptance
- Descriptor tests: transform/choice/abort protocol descriptors expose types, refs, mode, result refs, and deterministic fingerprints.
- Reinterpret tests: transform, choice, and abort source sites reinterpret to transform target; mapper resumes or returns source correctly.
- Composition tests: source-only interpreter returns `.reinterpreted`; composed source+target completes; unhandled target remains inspectable; forwarding still works.
- Effect-row tests: handled Program sites, protocol ops, reinterpreted sources, emitted targets, forwarded sites, residuals, duplicate handlers, fake/foreign descriptors.
- Trace/capsule tests: source request fingerprint, source capsule fingerprint, target payload fingerprint, reinterpret fingerprint, target response fingerprint, source continuation fingerprint, fresh restored tokens.
- Regression proof: existing Program.run, Session, Handler/Interpreter, Capsule, Protocol, semantic builder, examples, and lint remain green.

## Requirement-to-Test Traceability
| requirement | acceptance |
| --- | --- |
| protocol descriptors independent of Program sites | descriptor unit tests plus missing schema-ref compile-fail |
| typed reinterpreted request values | `.reinterpreted` result metadata tests and no-token/no-pointer field audit |
| handler reinterpret outcome | handler tests for transform/choice/abort sources and wrong-payload compile-fail |
| typed mappers | mapper resume/returnNow tests plus invalid source outcome compile-fail |
| interpreter support and composition | source-only, composed, unhandled-target, and forwarding tests |
| protocol-op handlers | protocol handler behavior tests plus duplicate/fake/foreign compile-fail |
| effect-row discipline | `effectRow` and assert helper tests for eliminated/residual/reinterpreted/emitted effects |
| trace metadata stability | trace tests for reinterpret fingerprint and unchanged existing version constants |
| examples/docs | `zig build run-protocol-reinterpretation`, docs assertions by review, existing example runners |

## Rollout/Monitoring
- Rollout path: implement on a feature branch from local `main`; do not mutate public root exports.
- Monitoring signals: focused test filters after each subsystem, example stdout showing source and target request fingerprints, full proof bundle before PR, PR summary explicitly confirming fingerprint version policy and non-goals.
- Handoff points: after descriptor/API tests pass; after interpreter composition tests pass; after docs/examples pass; after full lint/build/test proof.

## Rollback/Abort Criteria
- abort_trigger=public root widens; rollback_action=revert root/API exposure before continuing
- abort_trigger=Program.run or Program.Session stepping semantics change; rollback_action=revert runtime/session changes and re-scope through a new spec
- abort_trigger=request tokens become serializable/durable or protocol requests carry pointers/addresses; rollback_action=revert ProtocolRequest representation
- abort_trigger=existing trace/request/site/response/value/capsule fingerprint versions change without changed contents; rollback_action=revert fingerprint changes or isolate to separate reinterpret fingerprint
- abort_trigger=required existing example runner fails due to behavior change; rollback_action=revert implicated subsystem before adding more features
- abort_trigger=effect-row helpers cannot fail closed on duplicate/foreign/residual cases; rollback_action=withhold composition API and return to design

## Assumptions/Defaults
- assumption=local baseline is `main` at `32418797a54b753ff829c3b36432cb7218fe8b0b` as verified on May 11, 2026; confidence=high; verification_plan=implementation starts with `git status --short --branch && git rev-parse HEAD` and optional fetch if user permits ref updates
- assumption=protocol-op terminal `Result` defaults to `void`; confidence=medium; verification_plan=descriptor tests cover choice/abort default and explicit structured Result
- assumption=effect_middleware example is stretch; confidence=high; verification_plan=only implement after required example/proof is green
- assumption=duplicate protocol-op handlers fail closed instead of priority ordering; confidence=high; verification_plan=compile-fail fixture wired in build.zig
- assumption=mapper identity fingerprint is feasible but optional; confidence=medium; verification_plan=if comptime type/fn identity cannot be stable without pointer-like data, omit mapper fingerprint and document reason

## Decision Log
- decision_id=D1 decision=place protocol-level descriptors under `ability.ir.schema.Protocol.operation/op`, not `Program.protocol`; rationale=they are protocol constructors, not compiled Program call sites
- decision_id=D2 decision=descriptor options include `.Result` defaulting to `void` for protocol-level choice/abort terminal responses; rationale=target protocol requests have no enclosing Program result
- decision_id=D3 decision=add `Program.Morphism` as the static source-target witness used by handlers and effect rows; rationale=effect-row metadata must be explicit, inspectable, and not inferred from handler body control flow
- decision_id=D4 decision=reinterpreted requests are data-only and source continuation authority remains the capsule; rationale=prevents second runtime and durable-token misuse
- decision_id=D5 decision=composition fails closed on duplicate/fake/foreign protocol-op handlers; rationale=priority ordering would make effect rows ambiguous
- decision_id=D6 decision=add separate reinterpret fingerprint domain while preserving existing fingerprint versions; rationale=adds auditability without replay churn

## Decision Impact Map
- decision_id=D1 impacted_sections=Interfaces/Types/APIs Impacted, Data Flow, Tests/Acceptance follow_up_action=implement descriptor API before interpreter changes
- decision_id=D2 impacted_sections=Interfaces/Types/APIs Impacted, Edge Cases/Failure Modes, Requirement-to-Test Traceability follow_up_action=add choice/abort Result descriptor tests
- decision_id=D3 impacted_sections=Interfaces/Types/APIs Impacted, Data Flow, Effect-row tests, Implementation Brief follow_up_action=build Morphism before effect-row assertions
- decision_id=D4 impacted_sections=Data Flow, Rollback/Abort Criteria, Adversarial Findings follow_up_action=audit ProtocolRequest fields for token/pointer/address exclusion
- decision_id=D5 impacted_sections=Edge Cases/Failure Modes, Tests/Acceptance follow_up_action=add duplicate protocol-op compile-fail fixture
- decision_id=D6 impacted_sections=Trace tests, Rollback/Abort Criteria follow_up_action=assert existing fingerprint versions unchanged

## Open Questions
None; owner=n/a; due_date=n/a; default_action=n/a

## Stakeholder Signoff Matrix
| product | engineering | operations | security |
| --- | --- | --- | --- |
| owner=Ability maintainer; status=ready_for_implementation | owner=implementation agent; status=ready_with_api_constraints | owner=implementation agent; status=local_proof_required_no_runtime_rollout | owner=implementation agent; status=token/pointer/durable-id constraints required |

## Adversarial Findings
- lens=feasibility type=risks severity=medium section=Interfaces/Types/APIs Impacted decision=D2 status=mitigated probability=medium impact=high trigger=target choice/abort needs terminal Result without enclosing Program
- lens=operability type=risks severity=medium section=Data Flow decision=D4 status=mitigated probability=medium impact=high trigger=reinterpreted request accidentally stores tokens, pointers, or allocator addresses
- lens=risk type=risks severity=high section=Rollback/Abort Criteria decision=D4,D6 status=mitigated probability=low impact=high trigger=Session semantics or existing fingerprint versions drift
- lens=verification type=preferences severity=low section=Tests/Acceptance decision=D3 status=accepted probability=low impact=low trigger=mapper identity fingerprint not stable enough to include
- taxonomy_summary errors=0 risks=3 preferences=1

## Convergence Evidence
clean_rounds=2
press_pass_clean=true
new_errors=0
last_two_iterations_delta_kind=none,none
press_sections_checked=Interfaces/Types/APIs Impacted,Data Flow,Tests/Acceptance,Rollback/Abort Criteria
hysteresis=passed
implementation_ready=true
remaining_minor_concerns=mapper_identity_fingerprint_feasibility_optional

## Contract Signals
contract_version=2
strictness_profile=balanced
blocking_errors=0
material_risks_open=0
clean_rounds=2
press_pass_clean=true
new_errors=0
rewrite_ratio=0.00
external_inputs_trusted=false
improvement_exhausted=true
stop_reason=none
plan_contract_lint=skipped_stdin_unsupported

## Implementation Brief
| step | owner | success_criteria |
| --- | --- | --- |
| 1. Reconfirm baseline | implementation agent | `git status --short --branch`, `git rev-parse HEAD`, and `zig version` captured before edits |
| 2. Add protocol-level descriptors | implementation agent | descriptor tests pass for transform/choice/abort refs, Result defaults, schema refs, and deterministic fingerprints |
| 3. Add Morphism and ProtocolRequest | implementation agent | typed request metadata/fingerprint tests pass and representation excludes tokens/pointers/addresses |
| 4. Add handler reinterpret and mapper validation | implementation agent | source transform/choice/abort reinterpret tests pass; invalid payload/outcome compile-fail fixtures pass |
| 5. Extend Interpreter and composition | implementation agent | source-only `.reinterpreted`, composed completion, unhandled target, forwarding, and manual host response tests pass |
| 6. Add effect-row helpers | implementation agent | eliminated/residual/reinterpreted/emitted assertions pass; duplicate/fake/foreign handlers fail closed |
| 7. Add trace metadata, example, docs, build wiring | implementation agent | `run-protocol-reinterpretation` prints source/target fingerprints and both allow/deny outcomes; docs preserve non-goals |
| 8. Close proof bundle | implementation agent | all proof commands from the spec pass, or only environment blockers remain with exact command/error evidence |

Iteration: 3
