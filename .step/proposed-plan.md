Iteration: 6

# ProgramPlan Scalar Hardening Plan

## Round Delta
- Tightened the prior plan with exact edit placement: remove only the eager `after_stack` reservation; add overlap validation immediately after per-function span bounds and before reachability arrays are consumed.
- Added a small helper strategy for overlap checks and allocation telemetry so implementation does not invent policy mid-edit.
- No scope change from the confirmed `$grill-me` brief.

## Summary
Harden the current scalar `ability.program` executable subset without widening semantics. First wave: change `InterpreterScratch.init` so `after_stack` starts empty and grows only through `pushAfter`, while preserving the existing per-frame `max_interpreter_steps` pending-after guard and global step budget. Second wave: add early `ProgramPlan.validate` overlap rejection for function-owned block and instruction spans, using precise errors. Completion bar: focused allocation/span tests pass, then the full requested Zig proof bundle passes.

## Non-Goals/Out Of Scope
- No product/sum/string-list execution, no public `ability.program` API change, no `return_error` reachability work, no package/lint guard, no broad `ProgramPlan` redesign.
- Do not reject shared requirement, output, or local descriptor spans unless an existing execution invariant already rejects them.

## Scope Change Log
scope_change=none; reason=confirmed hardening-only scope retained; approved_by=user

## Interfaces/Types/APIs Impacted
- `src/lowering_api.zig`: implementation-only scratch allocation change; keep `max_interpreter_steps`, shared locals scratch, shared call-arg scratch, frame after marks, reverse unwinding, and terminal bypass behavior.
- `src/internal/program_plan.zig`: add `OverlappingFunctionBlockSpan` and `OverlappingFunctionInstructionSpan` to `ValidationError`; update `invalidGeneratedPlan` messages for exhaustive switch coverage.
- `test/program_api_test.zig`: extend `CountingAllocator` with `total_allocated_bytes` and `largest_allocation_request` or equivalent byte telemetry.
- `src/internal_program_plan.zig`: no new surface unless the existing `ValidationError` alias naturally exposes the added errors.

## Data Flow
- Runtime allocation: `InterpreterScratch.init` still reserves locals and call args from `entryExecutionAnalysis`, but does not reserve `after_stack`; `pushAfter` remains the only after-stack growth path.
- Runtime safety: before `pushAfter`, keep `scratch.frameAfterStack(frame).len >= max_interpreter_steps` rejection; keep `remaining_steps` decrement logic unchanged.
- Validation: after each function's block/instruction ranges are proven in-bounds, call a local overlap validator before `markFunctionReachableBlocks`, completion reachability, terminal reachability, or `entryExecutionAnalysis`-sensitive logic can infer ownership.

## Edge Cases/Failure Modes
- Half-open spans: `[start, end)` overlaps only when both spans are non-empty and `a_start < b_end and b_start < a_end`.
- Zero-length instruction spans own no instruction and may share a boundary/start.
- Adjacent non-overlapping spans must be accepted.
- Do not keep stale `ArrayList` slices across any scratch operation that may reallocate; recompute `locals = scratch.frameLocals(frame)` after helper/scratch operations as current code already does.

## Tests/Acceptance
- Allocation tests: no-after plan does not allocate after-stack storage; one-after plan's largest allocation request is below `max_interpreter_steps * @sizeOf(u16)`; looped-after plan pushes more dynamic continuations than static reachable-after count and returns expected value.
- Scratch regression tests: keep deep-helper and many-after tests meaningful with stable upper bounds, not exact allocation counts.
- Validation tests: reject exact and partial function block-span overlaps; reject exact and partial function instruction-span overlaps; accept adjacent non-overlapping spans.
- Full proof: `zig version`; `zig fmt --check build.zig src examples test bench`; `git diff --check`; `zig build --summary all`; `zig build test --summary all`; `zig build lint -- --max-warnings 0`.

## Requirement-To-Test Traceability
- Lazy after allocation -> no-after and one-after allocation tests.
- Dynamic cap preservation -> looped-after execution plus existing `max_interpreter_steps` guard.
- Shared scratch preservation -> deep-helper/many-after shared scratch tests.
- Unambiguous block ownership -> duplicate/partial/adjacent block-span tests.
- Unambiguous instruction ownership -> duplicate/partial/adjacent instruction-span tests.
- Scope discipline -> no structured-codec fixtures and full proof bundle.

## Rollout/Monitoring
- Local branch hardening only; no migration or runtime schema rollout.
- Before final delivery, inspect diff scope and verify no public-facing docs/examples were changed unless required by compiler fallout.

## Rollback/Abort Criteria
- Abort if implementation weakens `max_interpreter_steps`, reintroduces per-helper scratch allocation, or stores stale slices across reallocating operations.
- Abort if overlap validation rejects non-execution metadata sharing.
- Replace any exact allocation-count assertion with byte/request upper bounds if allocator behavior proves noisy.

## Assumptions/Defaults
- confidence=high; assumption=`zig version` should be `0.16.0`; verification=`zig version`.
- confidence=high; assumption=half-open span semantics are intended for ownership; verification=adjacent accepted test.
- confidence=medium; assumption=largest allocation request is the least brittle signal for the old eager allocation; verification=focused one-after test.
- date=2026-05-07; assumption=current `main` still has eager after-stack reservation; verification=`rg after_stack.ensureTotalCapacity`.

## Decision Log
- D1: no initial after-stack reservation; preserves safety while removing coarse allocation.
- D2: largest-request allocation proof; catches old full-buffer reservation without brittle event counts.
- D3: half-open span overlap; empty spans own nothing.
- D4: precise overlap errors; ambiguous ownership is distinct from out-of-range spans.
- D5: validate overlap before reachability; execution analysis can assume unique owners.

## Decision Impact Map
- decision_id=D1 impacted_sections=Data Flow, Implementation Brief follow_up_action=delete only the eager after-stack ensureTotalCapacity block.
- decision_id=D2 impacted_sections=Tests/Acceptance follow_up_action=extend CountingAllocator byte telemetry.
- decision_id=D3 impacted_sections=Validation Tests follow_up_action=include adjacent accepted case.
- decision_id=D4 impacted_sections=Interfaces/Types/APIs follow_up_action=extend ValidationError and diagnostic switch.
- decision_id=D5 impacted_sections=Data Flow follow_up_action=call overlap validator before reachability work.

## Open Questions
None.

## Stakeholder Signoff Matrix
| area | owner | status |
| --- | --- | --- |
| product | user | confirmed hardening-only |
| engineering | implementer | ready |
| operations | n/a | no rollout |
| security | n/a | no security surface change |

## Adversarial Findings
- lens=feasibility type=risk severity=low section=Tests decision=D2 status=mitigated probability=medium impact=low trigger=allocator internals vary; mitigation=largest-request upper bound.
- lens=operability type=risk severity=low section=Interfaces decision=D4 status=accepted probability=low impact=low trigger=error-set churn; mitigation=precise names and local diagnostic update.
- lens=risk type=preference severity=low section=Scope decision=D5 status=closed probability=low impact=medium trigger=late validation leaves analysis exposed; mitigation=early validation placement.

## Convergence Evidence
clean_rounds=2
press_pass_clean=true
new_errors=0
blocking_errors=0
material_risks_open=0
press_sections_checked=Summary, Data Flow, Tests/Acceptance, Implementation Brief
implementation_ready=true

## Contract Signals
contract_version=2
strictness_profile=balanced
blocking_errors=0
material_risks_open=0
clean_rounds=2
press_pass_clean=true
new_errors=0
rewrite_ratio=0.22
external_inputs_trusted=true
improvement_exhausted=true
stop_reason=none

## Implementation Brief
1. step=interpreter owner=implementer success_criteria=remove the `analysis.reachable_after_count != 0` after-stack pre-reservation from `InterpreterScratch.init` and leave the push-time cap intact.
2. step=telemetry owner=implementer success_criteria=extend `CountingAllocator` to track total allocated bytes and largest allocation request without changing child allocator behavior.
3. step=allocation_tests owner=implementer success_criteria=add no-after, one-after, and looped-after tests using largest-request bounds and expected execution results.
4. step=span_validation owner=implementer success_criteria=add a local O(n²) overlap helper over function block/instruction half-open ranges, called before reachability analysis.
5. step=validation_tests owner=implementer success_criteria=cover exact overlap, partial overlap, and adjacent acceptance for block and instruction spans.
6. step=proof owner=implementer success_criteria=run all requested Zig proof commands and report any blocked lane explicitly.
