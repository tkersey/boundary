Iteration: 6

# Ability ProgramPlan Structured-Runway Execution Plan

## Round Delta
- Replaced the narrow "scalar contract fence" plan with the confirmed `$grill-me` frame: a durable structured-runway execution spine.
- Locked shared all-frame scratch, helper-cycle rejection, static entry reachability, allocation-count proof, and no public API expansion.
- Added one governing internal analysis artifact so support gating and scratch bounds share the same source of truth.

## Summary
Implement this as an internal execution-spine hardening pass: `ability.program` still executes only scalar codecs, but `ProgramPlan` gains an internal entry-execution analysis used by both `validateExecutablePlanSupport` and the interpreter scratch allocator. First build the analysis and support predicate, then refactor interpreter scratch around it, then lock behavior with scalar positives, structured negatives, unreachable-structured acceptance, allocation-count proof, README updates, and the full requested Zig proof bundle.

Done means: no structured execution is added, unsupported entry-reachable shapes fail early with precise errors, acyclic helper behavior is preserved, helper cycles are rejected, scratch is per-run and bounded as `O(plan + budgeted after)`, allocation pressure is measurably lower, and all proof commands pass.

## Non-Goals / Out Of Scope
- Do not implement product, sum, or string-list execution.
- Do not widen the public root surface or add public `ability.ir` APIs unless implementation proves direct tests impossible.
- Do not redesign `ProgramPlan` wire shape or validation semantics.
- Do not add lint coverage guard or compile-fail harness unless trivial existing support appears.
- Do not reintroduce removed public APIs.

## Implementation Brief
- step=analysis; owner=implementer; success_criteria=`entryExecutionAnalysis` computes static reachability, helper cycles, and scratch bounds without changing validation semantics.
- step=support-gate; owner=implementer; success_criteria=all entry-reachable unsupported codecs and helper cycles fail with precise `Unsupported*` errors before `ProgramValueTypeForCodec`.
- step=scratch; owner=implementer; success_criteria=`InterpreterScratch` owns locals/call args/after/frame marks per run and recursive helper execution uses it without stale slices.
- step=tests; owner=implementer; success_criteria=scalar positives, structured negatives, unreachable structured acceptance, helper-cycle rejection, behavior regressions, leak checks, and allocation-count proof pass.
- step=docs; owner=implementer; success_criteria=README clearly separates valid rich IR from scalar executable IR and documents string/output ownership limits.
- step=proof; owner=implementer; success_criteria=run `zig version`, `zig fmt --check build.zig src examples test bench`, `git diff --check`, `zig build --summary all`, `zig build test --summary all`, and `zig build lint -- --max-warnings 0`.
