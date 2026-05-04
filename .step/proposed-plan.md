Iteration: 6

# Plan: ProgramPlan-Centered Generalized Algebraic Effects Migration

## Round Delta
- Integrated the locked `$grill-me` brief: one big PR, hard break from `Body.program`, all built-ins migrated, full Cartesian generated matrix.
- Expanded first wave from custom GAE restoration to full first-order GAE core: public builder DSL, derived struct/enum codecs, general ProgramPlan interpreter, strict resource unwind parity.
- Kept deliberate exclusions: no public ArtifactV1/compile, no source-like Zig syntax, no native execution fallback, no performance gate.

## Summary
Implement one migration PR that makes `ability.program` the only public plan-backed semantic constructor for generalized algebraic effects. First execution wave replaces the current `Body.program(runtime, handlers)` contract with a public minimal builder DSL that lowers to `ProgramPlan`; the completion bar is full generated Cartesian capability coverage across custom Transform/Choice/Abort, all built-ins, derived struct/enum codecs, JSON roundtrip, one-shot enforcement, and full repo verification.

Done means: every public `ability.program` exposes and runs `compiledPlan()`, all old direct-body examples/tests are rewritten or removed, all built-in effects execute through the same ProgramPlan interpreter, and no README/API claim ships until the full matrix and closure lanes pass.

## Rewrite Justification
The prior plan targeted a smaller custom-effect restoration. The `$grill-me` answers expanded scope beyond 35% by requiring all built-ins, struct/enum codecs now, a general interpreter, strict resource parity, full Cartesian testing, and one big PR. Incremental patching would hide scope changes; a full replacement plan is safer.

## Iteration Change Log
- iteration=4 focus=grill-handoff round_decision=continue delta_kind=material evidence=locked answers from `$grill-me` what_we_did=converted decisions into implementation contract change=expanded to all built-ins/full matrix/one big PR sections_touched=Summary,Interfaces,Tests,DecisionLog
- iteration=5 focus=adversarial-press round_decision=continue delta_kind=none evidence=feasibility/operability/risk pass found risks but no unresolved choices what_we_did=checked interpreter/codecs/resource/matrix boundaries change=no material delta sections_touched=AdversarialFindings,Rollback
- iteration=6 focus=closure round_decision=close delta_kind=none evidence=all major requirements map to tests and no open questions remain what_we_did=closed plan with implementation campaign change=no material delta sections_touched=ContractSignals,ImplementationBrief

## Non-Goals / Out Of Scope
- No public `ability.compile`, ArtifactV1, package/runtime artifact API, or public VM packaging in this PR.
- No source parser or ordinary Zig-looking body lowering.
- No native execution fallback under `ability.program`.
- No nested/scoped handlers, open-row polymorphism, or multi-shot continuations.
- No performance budget; correctness gates only.

## Scope Change Log
scope_change=major expansion; reason=`$grill-me` locked full first-order core, all built-ins, derived codecs, full matrix; approved_by=user

## Interfaces / Types / APIs Impacted
- `ability.program(label, HandlersType, Body)` requires `Body.plan(builder)` or equivalent lowerable builder entrypoint and rejects `Body.program(runtime, handlers)`.
- `ability.effect.Define` and `ability.effect.ops.{Transform,Choice,Abort}` return as public custom-effect authoring surface.
- Add `ability.ir` as a public minimal builder namespace for rows, functions, blocks, locals, op calls, helper calls, branches, returns, outputs, and codec declarations.
- Extend `ProgramPlan` schema as breaking current-version change: product/sum codecs, plan-derived result/output metadata, continuation-use metadata, and built-in lifecycle/output data.
- `Program.Result` is derived from plan return/output declarations; ownership/deinit comes from codec/output metadata, not `Body.deinitResult`.
- Add a general ProgramPlan interpreter replacing the current single-dispatch runner limitation.

## Data Flow
`Define/ops` or built-in descriptors define an effect row -> public builder emits concrete top-level-row Ability IR -> ProgramPlan lowering validates row, functions, codecs, outputs, continuations, and built-in lifecycle metadata -> `compiledPlan()` exposes the validated plan -> `Program.run(runtime, handlers)` executes through the general interpreter -> handlers are invoked only via declared effect operations -> result/output ownership is decoded from plan metadata.

## Edge Cases / Failure Modes
- Old body contract present: compile error, with migration pointer to builder entrypoint.
- Unsupported struct/enum field: compile error; no string packing fallback.
- Handler row mismatch: compile error or validation error naming missing requirement/op.
- Double resume: fail closed via continuation-use state.
- Resource abort/error path: release must run exactly once and preserve current strict unwind behavior.
- JSON roundtrip loses schema detail: release blocker.
- Matrix generation hides a broken cell: generated cases must include stable case IDs and focused filters.

## Tests / Acceptance
- Generated full Cartesian matrix covering: custom Transform/Choice/Abort, all built-ins, derived scalar/product/sum codecs, success/error/abort paths, one-shot violation, JSON roundtrip, and result/output ownership.
- Focused suites: `program-plan-gae-core`, `program-plan-codecs`, `program-plan-builtins`, `program-plan-resource-unwind`, `program-plan-matrix`.
- Negative tests: `Body.program` rejected, unsupported codec rejected, row mismatch rejected, double resume rejected.
- Examples: rewrite state, writer, custom approval, and one resource workflow to builder-backed `ability.program`.
- Closure lanes: `zig build`, `zig build test --summary none`, `zig build lint -- --max-warnings 0`, plus focused matrix suites.

## Requirement-to-Test Traceability
- R1 hard-break direct bodies -> negative `Body.program` compile test.
- R2 custom GAE support -> custom Transform/Choice/Abort matrix rows.
- R3 all built-ins migrated -> built-in matrix rows and rewritten examples.
- R4 struct/enum codecs -> product/sum codec derivation and JSON roundtrip tests.
- R5 general interpreter -> helper/block/branch/op-call runtime tests.
- R6 resource parity -> abort/error/normal strict-unwind tests.
- R7 one-shot continuation -> double-resume failure test.
- R8 no public artifact restore -> root/API probe asserts no public compile/ArtifactV1 surface.

## Rollout / Monitoring
- Land as one PR, but implement internally in dependency order: schema/codecs, builder, lowering, interpreter, built-ins, matrix, docs.
- Do not update README to claim GAE completeness until matrix and full closure pass.
- PR description must list removed surfaces, new public builder surface, generated matrix command, and all proof lanes.

## Rollback / Abort Criteria
- Abort if `Program.run` keeps any direct Zig body fallback.
- Abort if resource cleanup cannot match strict unwind parity.
- Abort if derived product/sum codecs cannot JSON roundtrip through ProgramPlan.
- Rollback as one PR revert; partial revert is unsafe because API, docs, examples, and tests change together.

## Assumptions / Defaults
- assumption=breaking ProgramPlan schema is acceptable; confidence=high; verification=tests delete legacy-upgrade expectations or update them to current-only.
- assumption=builder is primary authoring API; confidence=high; verification=docs/examples use builder without source-syntax promises.
- assumption=concrete top-level rows are enough for first-order core; confidence=high; verification=no helper test depends on row polymorphism.
- assumption=no perf gate; confidence=high; verification=do not block on benchmark deltas.

## Decision Log
- D1: `ability.program` is plan-backed only.
- D2: public builder DSL is primary authoring surface.
- D3: custom effects and all built-ins execute through one ProgramPlan interpreter.
- D4: struct/enum codecs ship now via comptime derivation.
- D5: continuations are one-shot and enforced.
- D6: full Cartesian generated matrix gates public GAE claim.
- D7: no public ArtifactV1/compile restoration.

## Decision Impact Map
- decision_id=D1 impacted_sections=Interfaces,Tests,Rollback follow_up_action=remove direct body path.
- decision_id=D2 impacted_sections=Interfaces,Examples,Docs follow_up_action=design minimal `ability.ir` builder.
- decision_id=D3 impacted_sections=DataFlow,Tests follow_up_action=migrate built-ins.
- decision_id=D4 impacted_sections=ProgramPlan,Serialization,Tests follow_up_action=bump schema and add derived codecs.
- decision_id=D5 impacted_sections=Interpreter,Runtime,Tests follow_up_action=track continuation-use state.
- decision_id=D6 impacted_sections=Build,CI,PR follow_up_action=add generated focused matrix.
- decision_id=D7 impacted_sections=RootAPI,Docs follow_up_action=assert no public artifact surface.

## Open Questions
None; owner=n/a due_date=n/a default_action=execute locked brief.

## Stakeholder Signoff Matrix
product=locked engineering=ready operations=ready security=ready status=plan complete, implementation pending

## Adversarial Findings
- lens=feasibility type=risk severity=high section=Interpreter decision=general ProgramPlan runner status=mitigated probability=medium impact=high trigger=branch/helper/op execution diverges from validation.
- lens=operability type=risk severity=high section=Tests decision=full Cartesian matrix status=accepted probability=high impact=medium trigger=one big PR becomes hard to review.
- lens=risk type=risk severity=high section=Resource decision=strict unwind parity status=mitigated probability=medium impact=high trigger=abort/error cleanup differs from existing behavior.
- lens=api type=error severity=high section=Interfaces decision=native fallback status=resolved probability=low impact=high trigger=`Body.program` remains accepted.

## Convergence Evidence
clean_rounds=2; press_pass_clean=true; new_errors=0; checked_sections=Interfaces,Tests,Rollback,ImplementationBrief; implementation_ready=true

## Contract Signals
contract_version=2
strictness_profile=balanced
blocking_errors=0
material_risks_open=0
clean_rounds=2
press_pass_clean=true
new_errors=0
rewrite_ratio=0.7
external_inputs_trusted=false
improvement_exhausted=true
stop_reason=none

## Implementation Brief
- step=schema_and_codecs owner=Codex success_criteria=ProgramPlan schema bumped, product/sum/scalar codecs derive at comptime, JSON roundtrip passes.
- step=public_builder owner=Codex success_criteria=`ability.ir` builder can express rows, blocks, locals, op calls, helper calls, branches, returns, outputs.
- step=program_api_break owner=Codex success_criteria=`ability.program` rejects `Body.program`, requires builder-backed plan, exposes `compiledPlan()`.
- step=general_interpreter owner=Codex success_criteria=interpreter executes blocks, locals, branches, helper calls, op calls, returns, outputs, one-shot continuations.
- step=builtins_migration owner=Codex success_criteria=state, writer, reader, optional, exception, resource all run through ProgramPlan.
- step=custom_effect_restore owner=Codex success_criteria=`Define/ops` public and custom Transform/Choice/Abort matrix rows pass.
- step=matrix_and_docs owner=Codex success_criteria=generated full Cartesian focused suite passes, examples/README reflect only plan-backed APIs.
- step=closure owner=Codex success_criteria=focused suites plus `zig build`, `zig build test --summary none`, `zig build lint -- --max-warnings 0` pass.
