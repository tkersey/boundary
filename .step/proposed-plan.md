Iteration: 8

# Full ProgramPlan Convergence Campaign

## Round Delta
- Upgraded the prior campaign plan from roadmap-level sequencing to an implementation-ready branch contract.
- Added an internal conformance harness as the compounding proof surface for built-in migrations.
- Made typed ownership semantics explicit as a cross-cutting gate instead of letting it disappear between contract closure and writer/resource work.

## Summary
Converge `ability` around `ProgramPlan` as the single semantic execution kernel while preserving the small public root. The chosen path is a dependency-ordered campaign: first close the typed executable contract, then make plan authoring and examples usable, then migrate built-in effects onto plan-native execution in increasing lifecycle-risk order. The first wave is Branches 1-3; the campaign is complete when all built-ins have plan-native examples/tests or a documented design gate, compatibility APIs remain green, and the release hardening branch proves packaging, lint, docs, and proof coverage.

Completion requires: `ability.program(label, Handlers, Body)` remains the public front door; `ProgramValue` remains scalar-only; `ability.ir` owns the builder and raw plan escape hatch; `Program.contract` remains a read-only projection; no public ArtifactV1, VM, compile, parser, or generated custom effect surface returns.

## Iteration Change Log
- iteration=5; focus=baseline; round_decision=continue; delta_kind=scope_harden; evidence=prior plan covered 11 branches but not explicit ownership track; what_we_did=made typed ownership a cross-cutting gate; change=ownership tests/docs now land across Branches 1,2,6,9,11; sections_touched=Summary, Tests/Acceptance, Implementation Brief
- iteration=6; focus=architecture; round_decision=continue; delta_kind=feature_add; evidence=built-in parity would otherwise repeat bespoke tests; what_we_did=added internal conformance harness; change=contract/execution parity traces become reusable across Branches 4-9; sections_touched=Data Flow, Decision Log, Requirement-to-Test Traceability
- iteration=7; focus=operability; round_decision=continue; delta_kind=none; evidence=branch order, proof gates, rollback triggers, and non-goals are aligned; what_we_did=pressed rollout and abort criteria; change=no material delta; sections_touched=Rollout/Monitoring, Rollback/Abort Criteria
- iteration=8; focus=risk; round_decision=close; delta_kind=none; evidence=adversarial pass found no blocking ambiguity; what_we_did=verified traceability for every original ambition track; change=no material delta; sections_touched=Requirement-to-Test Traceability, Contract Signals

## Rewrite Justification
The prior artifact was directionally correct but still too high-level for implementation. Harm if kept: Branches 4-9 would each rediscover parity strategy, typed ownership would be implicit, and the builder surface would remain underspecified. Rewriting is beneficial because the campaign now has concrete gates, internal proof infrastructure, and branch-level acceptance criteria.

## Non-Goals/Out of Scope
- No new public root exports.
- No public ArtifactV1, VM, compile, source parser, or legacy capability-map surfaces.
- No widening of `ProgramValue`.
- No removal of compatibility APIs before plan-native examples and parity tests exist.
- No public custom effect authoring in the next few branches.
- No source-like syntax or compiler layer.
- No global registry for nested-with targets.

## Scope Change Log
- scope_change=full_campaign; reason=user asked for the full ambition; approved_by=user
- scope_change=add_internal_conformance_harness; reason=reduces repeated parity work across built-in migrations; approved_by=engineering-default
- scope_change=typed_ownership_cross_cutting_gate; reason=original ambition includes ownership semantics but near-term branch list did not give it a standalone branch; approved_by=engineering-default

## Interfaces/Types/APIs Impacted
- `src/root.zig`: remains limited to `effect`, `ir`, `program`, `Runtime`.
- `ability.ir`: expands builder ergonomics under the existing namespace; raw `ability.ir.plan.*` tables stay available.
- `ability.program`: strengthens private/internal validation of body hooks and diagnostics; public call shape stays unchanged.
- `Program.contract`: may gain projection data only for already-validated facts; it must not expose mutable plan tables or become an execution authority.
- `ability.effect.*`: compatibility APIs stay; plan-native paths are added as examples/internal lowering before any public migration.
- `effect_schema`: remains the source metadata vocabulary for state, reader, writer, optional, exception, and resource migrations.
- `test/` and `examples/`: gain reusable conformance fixtures and public-API examples.

## Data Flow
1. A body supplies `Body.compiled_plan` directly or through `ability.ir.builder`.
2. `ability.program` validates the plan, nested-with targets, typed schema table, entry args, result/output hooks, cleanup hooks, reachable `return_error` literals, and executable capability support.
3. Runtime execution uses interpreter-owned frames for entry, helpers, recursion, and nested-with targets.
4. Structured values flow through ProgramPlan value refs and exact `Body.value_schema_types`; scalar public carriers remain `ProgramValue`.
5. Built-in migrations lower effect semantics into ProgramPlan requirements, ops, payload/resume refs, sum branches, nested-with targets, and typed outputs.
6. `Program.Result.value` and `Program.Result.outputs` are cleaned independently through explicit hooks.
7. The internal conformance harness records contract metadata plus execution traces for raw plans, builder plans, and plan-native built-ins.

## Edge Cases/Failure Modes
- Reachable `return_error` missing from `Body.Error`: compile-time failure.
- Unreachable helper or post-terminal `return_error`: ignored for `Body.Error` and omitted from `Program.contract`.
- Schema table mismatch: diagnostic names schema, field, or variant table.
- Sum extraction destination mismatch: plan validation reports a sum-specific destination failure.
- Nested-with target missing or wrong: fail closed with metadata/function/result-codec diagnostic.
- Output collection failure after result creation: result cleanup runs; output cleanup does not.
- Writer output ownership: accumulator output must have explicit allocator ownership and cleanup.
- Exception/resource terminal paths: after hooks and releases must follow compatibility semantics.
- Resource release failure: preserve current error precedence before declaring parity.

## Tests/Acceptance
Every branch must pass:

```sh
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build test --summary all
zig build lint -- --max-warnings 0
```

Branch-specific acceptance:
- Branch 1: compile-fail fixtures for body hook mismatches; runtime tests for reachable/unreachable errors and cleanup failure paths.
- Branch 2: examples for typed product/sum execution, sum matching, contract inspection, outputs, and cleanup.
- Branch 3: builder-generated plans match raw plans in contract metadata and execution.
- Branches 4-9: compatibility behavior stays green while plan-native examples/tests are added.
- Branch 10: design artifact only; no public custom effect API exposure.
- Branch 11: package/lint guard verifies `.zig` coverage under `src`, `examples`, `test`, and `bench`.

## Requirement-to-Test Traceability
| Requirement | Acceptance Check |
|---|---|
| Typed contract closure | Branch 1 compile-fail and runtime contract tests |
| Public docs/examples | Branch 2 examples plus README concision review |
| Higher-level builder | Branch 3 raw-vs-builder contract parity tests |
| Plan-native optional | Branch 4 resume, return-now, after-resume, terminal tests |
| Plan-native state/reader | Branch 5 final-state output and borrowed reader environment tests |
| Plan-native writer | Branch 6 empty/one/many tell plus cleanup failure tests |
| Plan-native exception | Branch 8 scalar/product/sum throw-catch tests |
| Plan-native resource | Branch 9 LIFO, terminal escape, release failure, typed resource stress tests |
| Nested-with stabilization | Branch 7 nested-with matrix and contract projection tests |
| Typed ownership semantics | Branches 1,2,6,9,11 cleanup docs/tests |
| Custom effect authoring | Branch 10 schema-first design with explicit non-exposure |
| Packaging/release discipline | Branch 11 lint/package guard and full proof commands |

## Rollout/Monitoring
- Land as ordered, narrow PRs.
- Do not start built-in migration PRs until Branches 1-3 are merged.
- Each PR records full proof commands, focused lanes, changed public surface, and compatibility status.
- The conformance harness becomes required for Branches 4-9 once introduced.
- Monitor drift through contract metadata assertions, compatibility tests, and examples built through public APIs.

## Rollback/Abort Criteria
- Abort any branch that widens the public root or `ProgramValue`.
- Abort a builder change if it creates a second IR instead of producing `ProgramPlan`.
- Abort a built-in migration if compatibility behavior cannot be expressed in tests.
- Abort resource migration if optional/exception terminal behavior is not already stable.
- Revert a branch if full proof commands fail because of branch-owned changes and cannot be fixed narrowly.
- Defer custom effect authoring if built-in plan-native lifecycle semantics remain incomplete.

## Assumptions/Defaults
- assumption=latest_main_is_baseline; confidence=medium; verification_plan=refresh from latest `main` before implementation; date=2026-05-08
- assumption=current_partial_branch1_diff_is_foundation; confidence=medium; verification_plan=review dirty diff and preserve only in-scope edits
- assumption=branch_order_is_dependency_order; confidence=high; verification_plan=enforce Branches 1-3 before built-in migrations
- assumption=examples_must_use_public_api; confidence=high; verification_plan=scan examples for forbidden surfaces
- assumption=custom_authoring_is_design_only; confidence=high; verification_plan=assert no public `Define`/`ops` exposure in Branch 10

## Decision Log
- D1: Execute as ordered branch campaign, not a megabranch.
- D2: Treat Branches 1-3 as the foundation gate.
- D3: Add an internal conformance harness for contract and execution parity.
- D4: Migrate built-ins by increasing lifecycle risk: optional, state/reader, writer, nested-with, exception, resource.
- D5: Keep typed ownership semantics cross-cutting across contract, docs, writer, resource, and release hardening.
- D6: Add a higher-level builder under `ability.ir.builder` that only emits existing `ProgramPlan`.
- D7: Keep compatibility APIs until parity examples and tests exist.
- D8: Keep `Program.contract` projection-only.
- D9: Make custom effect authoring a design branch, not public API exposure.

## Decision Impact Map
| decision_id | impacted_sections | follow_up_action |
|---|---|---|
| D1 | Rollout, Implementation Brief | Keep PRs ordered and narrow |
| D2 | Tests, Rollback | Block built-ins until typed contract/docs/builder land |
| D3 | Data Flow, Tests | Build reusable parity fixtures before optional/state migrations |
| D4 | Implementation Brief | Preserve migration order |
| D5 | Tests, Docs | Add ownership checks across branches |
| D6 | Interfaces | Extend builder without adding a compiler/parser |
| D7 | Non-Goals, Rollback | Keep compatibility test lanes |
| D8 | Interfaces | Prevent contract from becoming mutable execution state |
| D9 | Branch 10 | Produce design only |

## Open Questions
None. owner=engineering; due_date=n/a; default_action=execute in branch order.

## Stakeholder Signoff Matrix
| stakeholder | owner | status |
|---|---|---|
| product | user | full ambition requested |
| engineering | implementer | campaign decision-complete |
| operations | implementer | proof gates defined |
| security | reviewer | no new public execution surfaces planned |

## Adversarial Findings
- lens=feasibility; type=risk; severity=medium; section=Implementation Brief; decision=D1; status=mitigated; probability=medium; impact=high; trigger=combining multiple built-ins in one branch
- lens=operability; type=risk; severity=medium; section=Tests/Acceptance; decision=D3; status=mitigated; probability=medium; impact=medium; trigger=bespoke parity tests diverge between built-ins
- lens=risk; type=risk; severity=high; section=Rollback/Abort Criteria; decision=D4; status=mitigated; probability=medium; impact=high; trigger=resource migration starts before terminal/abort behavior is proven
- lens=architecture; type=preference; severity=low; section=Interfaces; decision=D6; status=accepted; probability=low; impact=low; trigger=builder API may need refinement after examples

## Convergence Evidence
blocking_errors=0
material_risks_mitigated=3
clean_rounds=2
press_pass_clean=true
new_errors=0
sections_pressed=Summary, Interfaces, Tests/Acceptance, Rollback/Abort Criteria, Implementation Brief
implementation_ready=true

## Contract Signals
contract_version=2
strictness_profile=balanced
blocking_errors=0
material_risks_open=0
clean_rounds=2
press_pass_clean=true
new_errors=0
rewrite_ratio=0.82
external_inputs_trusted=true
improvement_exhausted=true
stop_reason=none

## Implementation Brief
1. step=Branch 1 typed contract closure; owner=engineering; success_criteria=Reachable errors, hook validation, diagnostics, cleanup, and contract projection are proven.
2. step=Branch 2 docs and examples; owner=engineering; success_criteria=README stays concise; deeper docs/examples cover typed execution, sums, outputs, cleanup, nested-with, and contract.
3. step=Branch 3 higher-level builder; owner=engineering; success_criteria=Builder covers scalar/product/sum branches and payload extraction; one example rewritten; raw-vs-builder parity passes.
4. step=Branch 4 plan-native optional; owner=engineering; success_criteria=Optional workflow executes through `ability.program`; sum matching drives resume/return-now behavior; compatibility tests remain green.
5. step=Branch 5 plan-native state and reader; owner=engineering; success_criteria=State final output appears in `Program.Result.outputs`; reader environment remains borrowed.
6. step=Branch 6 plan-native writer; owner=engineering; success_criteria=Accumulator output ownership and cleanup failure behavior are explicit and tested.
7. step=Branch 7 nested-with stabilization; owner=engineering; success_criteria=Full target matrix passes; metadata matching is documented; targets stay explicit.
8. step=Branch 8 plan-native exception; owner=engineering; success_criteria=Throw/catch supports scalar, product, and sum payloads with correct terminal and after-hook behavior.
9. step=Branch 9 plan-native resource; owner=engineering; success_criteria=LIFO release, release-before-outer-catch/return, error precedence, and typed resources pass stress tests.
10. step=Branch 10 custom effect authoring design; owner=engineering; success_criteria=Schema-first design exists; no public custom effect API is exposed.
11. step=Branch 11 release hardening; owner=engineering; success_criteria=Lint/package guards, file classification, roadmap docs, and full proof commands pass.
