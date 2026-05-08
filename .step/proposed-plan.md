Iteration: 4

# Full `ability.program` Execution Expansion

## Round Delta
- Supersedes the earlier ledger-first plan: the capability ledger is now the governance layer for a broader execution expansion.
- Incorporates `$grill-me` decisions: typed structured values, typed outputs, direct nested-with execution, explicit-stack helper cycles, capped diagnostics, and minor version bump.
- Adds a campaign-style one-patch execution order so the patch stays reviewable despite broad scope.

## Summary
Implement one broad `ability.program` patch that expands the executable ProgramPlan subset from scalar-only to typed pass-through structured execution, typed output materialization, direct nested-with rows, and helper cycles through an explicit interpreter call stack. First wave builds the typed value/schema foundation and capability ledger; later waves wire execution semantics, outputs, diagnostics, docs, versioning, and the proof matrix. Done means existing scalar behavior remains equivalent, newly supported surfaces pass targeted matrix tests, unsupported contract violations fail closed, and `zig build`, `zig build test --summary none`, and `zig build lint -- --max-warnings 0` pass.

## Iteration Change Log
- iteration=1; focus=baseline; round_decision=continue; delta_kind=major; evidence=`$grill-me` confirmed full expansion; what_we_did=reframed from ledger-first to execution-first; change=ledger becomes proof/governance layer; sections_touched=summary,scope,interfaces
- iteration=2; focus=interfaces; round_decision=continue; delta_kind=major; evidence=locked Body APIs and public compatibility constraints; what_we_did=made schema/result/arg/output contracts decision-complete; change=typed per-Program model, no generic carrier; sections_touched=interfaces,data_flow,edge_cases
- iteration=3; focus=risk; round_decision=continue; delta_kind=major; evidence=mitigated host-stack and diagnostic risks; what_we_did=replaced recursive helper execution with explicit stack and capped blocker output; change=safer runtime and compile diagnostics; sections_touched=risks,tests,rollback
- iteration=4; focus=closure; round_decision=close; delta_kind=none; evidence=press pass covered APIs/tests/rollback with no open blockers; what_we_did=verified traceability and non-goals; change=no material delta; sections_touched=traceability,contract_signals,implementation_brief

## Non-Goals/Out of Scope
- No field access, variant inspection, projection, mutation, or other IR operations over structured values.
- No generated schema types; users provide `Body.value_schema_types`.
- No output label remapping; output labels must be valid Zig field identifiers.
- No generic public structured carrier and no `ProgramValue` variant expansion.
- No stable public record ordering; only ledger tags and fields are stable append-only.

## Scope Change Log
scope_change=expanded; reason=`$grill-me` answers moved target from diagnostic ledger to full execution expansion; approved_by=user confirmation

## Interfaces/Types/APIs Impacted
- `Body.value_schema_types = .{ Type0, Type1, ... }` maps one Zig type to each `compiled_plan.value_schemas` index; length and shape mismatches are compile errors.
- `Body.encodeStructuredArgs(handlers)` returns a typed tuple matching entry parameter order; scalar `Body.encodeArgs` remains unchanged for scalar-only programs.
- `Program.Result.value` uses the mapped Zig type for structured entry results and existing scalar types for scalar results.
- `Program.Result.outputs` becomes a generated typed struct for entry outputs; field names are output labels and labels must be valid Zig identifiers.
- `Body.deinitOutputs(allocator, outputs)` is required for non-void outputs and is called by `Result.deinit`.
- Capability ledger exposes stable append-only tags and fields on the returned Program type; message text and record order are not compatibility promises.
- `build.zig.zon` package version bumps from `0.2.0` to the next minor version.

## Data Flow
`Body.compiled_plan` validates structurally, then `value_schema_types` validates every schema by index. Program construction derives typed entry args, result type, internal per-Program execution storage, output struct type, and ledger records. `Program.run` encodes scalar args through the existing path, structured args through typed tuple validation, executes instructions through the typed interpreter, collects outputs from handler fields whose names match entry output labels, then returns `Result { value, outputs }`.

## Edge Cases/Failure Modes
- Schema mapping missing, wrong length, wrong codec, or wrong field/variant shape: compile error.
- Invalid output label for a typed struct field: compile error.
- Missing handler field for declared output label: compile error.
- Missing `Body.deinitOutputs` when outputs are non-void: compile error.
- Handler `finish` errors: declared errors propagate; undeclared errors map to `ProgramContractViolation`.
- Complete but unresolved `call_nested_with`: ledger blocker and enriched compile error, capped at 64 blockers.
- Helper cycles: execute through explicit stack and step budget; no host recursion dependency.
- Structured values are pass-through only; attempting scalar-only instructions on structured locals remains a contract violation or validation error.

## Tests/Acceptance
- Add capability matrix tests for product, sum, and `[]const []const u8` across entry args, results, op payloads, op resumes, helper params/results, and locals.
- Add nested structured schema tests covering recursive product/sum/list values.
- Add output materialization tests for valid typed outputs, invalid labels, missing finishers, finish errors, and required `deinitOutputs`.
- Add nested-with tests for direct execution and unresolved-row ledger blockers.
- Add helper-cycle tests proving explicit-stack execution is budget-bounded and avoids host recursion assumptions.
- Add ledger tests for stable tags/fields, deterministic non-contract order, capped diagnostics, and unchanged scalar support.
- Run `zig build`, `zig build test --summary none`, and `zig build lint -- --max-warnings 0`.

## Requirement-to-Test Traceability
- R1 structured execution -> codec matrix tests.
- R2 typed schema mapping -> compile-fail and positive shape tests.
- R3 output materialization -> output struct, finisher, error, and cleanup tests.
- R4 nested-with support -> direct execution plus unresolved blocker tests.
- R5 helper-cycle safety -> explicit-stack cycle and budget tests.
- R6 ledger governance -> stable field/tag and capped diagnostic tests.
- R7 compatibility -> existing scalar Program tests remain green.

## Rollout/Monitoring
- Ship as a minor package version bump with README and API comments documenting compatibility changes.
- No runtime deployment monitoring is needed; this is a library compile/runtime behavior change.
- Treat proof matrix failures as release blockers.

## Rollback/Abort Criteria
- Abort if scalar behavior regresses, `ProgramValue` must gain public variants, helper cycles require host recursion, or outputs cannot be cleaned deterministically.
- Roll back by restoring scalar-only support checks and `Program.Result.outputs = void`.
- Do not keep partial structured support without ledger/tests proving exact supported surfaces.

## Assumptions/Defaults
- Zig 0.16.0 remains the target; confidence=high; verification=`build.zig.zon`.
- One patch means one change set, not one unordered edit; confidence=high; verification=implementation brief checkpoints.
- `value_schema_types` can be validated fully at comptime; confidence=medium; verification=compile-fail matrix.
- No external time-sensitive dependency beyond current repo state as of 2026-05-07.

## Decision Log
- D1: Make execution expansion primary and ledger governance secondary.
- D2: Use Body-provided index-aligned schema types instead of generated schema types.
- D3: Keep structured values pass-through only.
- D4: Preserve `ProgramValue` by using per-Program typed structured execution.
- D5: Materialize outputs as typed structs and require `Body.deinitOutputs`.
- D6: Execute nested-with rows directly where resolvable.
- D7: Use explicit helper call stack for cycles.
- D8: Cap enriched compile diagnostics at 64 blockers and stabilize tags/fields only.
- D9: Bump minor package version.

## Decision Impact Map
- decision_id=D1; impacted_sections=summary,interfaces,tests; follow_up_action=ledger implemented after typed support foundation
- decision_id=D2; impacted_sections=interfaces,edge_cases; follow_up_action=compile-time schema validator
- decision_id=D4; impacted_sections=data_flow,rollback; follow_up_action=do not edit public `ProgramValue` variants
- decision_id=D5; impacted_sections=outputs,tests; follow_up_action=require finisher/deinit proof
- decision_id=D7; impacted_sections=runtime,tests; follow_up_action=replace recursive helper execution
- decision_id=D9; impacted_sections=rollout; follow_up_action=update version and README compatibility note

## Open Questions
None.

## Stakeholder Signoff Matrix
product=confirmed full expansion; engineering=decision-complete; operations=n/a library change; security=no new external boundary

## Adversarial Findings
- lens=feasibility; type=risk; severity=high; section=interfaces; decision=D2; status=mitigated; probability=medium; impact=high; trigger=schema/type validation becomes too large for one patch
- lens=operability; type=risk; severity=high; section=runtime; decision=D7; status=mitigated; probability=medium; impact=high; trigger=helper cycles consume unbounded stack or budget
- lens=risk; type=risk; severity=medium; section=outputs; decision=D5; status=mitigated; probability=medium; impact=medium; trigger=owned output cleanup is missing or inconsistent
- lens=compatibility; type=risk; severity=medium; section=rollout; decision=D9; status=accepted; probability=medium; impact=medium; trigger=public Program result/output shape changes affect users

## Convergence Evidence
blocking_errors=0; material_risks_open=0; clean_rounds=2; press_pass_clean=true; new_errors=0; sections_pressed=interfaces,tests,rollback,non_goals

## Contract Signals
contract_version=2
strictness_profile=balanced
blocking_errors=0
material_risks_open=0
clean_rounds=2
press_pass_clean=true
new_errors=0
rewrite_ratio=0.72
external_inputs_trusted=false
improvement_exhausted=true
stop_reason=none

## Rewrite Justification
The previous plan centered on a diagnostic capability ledger. `$grill-me` deliberately expanded the target to full executable support for structured values, outputs, nested-with, and helper cycles, so an incremental edit would preserve the wrong governing objective.

## Implementation Brief
1. step=establish typed schema validation; owner=implementer; success_criteria=`Body.value_schema_types` accepts exact mappings and rejects wrong length/shape/codecs.
2. step=build per-Program typed execution value model; owner=implementer; success_criteria=structured values flow through args, locals, helpers, ops, and results without changing `ProgramValue`.
3. step=replace helper recursion with explicit call stack; owner=implementer; success_criteria=cycle tests are budget-bounded and host-stack-independent.
4. step=execute `call_nested_with` rows directly; owner=implementer; success_criteria=resolvable rows run and unresolved rows emit ledger blockers.
5. step=materialize typed outputs; owner=implementer; success_criteria=handler `finish` collection, error mapping, and `Body.deinitOutputs` cleanup are tested.
6. step=add capability ledger and capped diagnostics; owner=implementer; success_criteria=stable tags/fields, capped 64-blocker compile errors, and deterministic records.
7. step=update README/API comments/version; owner=implementer; success_criteria=docs describe compatibility changes, non-goals, and new Body hooks.
8. step=run proof suite; owner=implementer; success_criteria=targeted matrix plus `zig build`, `zig build test --summary none`, and `zig build lint -- --max-warnings 0` pass.
