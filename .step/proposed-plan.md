# Compositional ProgramPlan Layout Builder

## Summary
Build `ability.ir.builder.layout` as an additive comptime authoring layer under
the existing `ability.ir.builder` namespace. The layout builder computes
ordinary function/local/block/instruction/terminator layout and emits the
existing `ability.ir.ProgramPlan` through existing validation.

The branch must not add new execution semantics, value codecs, `ProgramValue`
cases, custom effect authoring, Artifact/VM/compile/parser/source-language
APIs, public root exports, compatibility API removals, or broad built-in
migrations.

## Acceptance
- `ability.ir.builder.layout.finish` and `finishWithNestedTargets` accept nested
  specs and return validated `ability.ir.ProgramPlan` values.
- Layout computes function local/block/instruction spans and block instruction
  spans/terminator indexes.
- Required examples `examples/typed_program_plan.zig` and
  `examples/plan_native_optional.zig` use the layout builder and keep stdout
  stable.
- `Program.contract` tests prove label, result refs, entry parameters, schemas,
  fields, variants, requirements, ops, modes, payload refs, resume refs,
  after-hook flags, and outputs.
- Raw ProgramPlan APIs and fixed builder compatibility helpers remain available.
- Docs explain raw tables, layout builder boundaries, validation, and
  `Program.contract` proof.

## Proof
```sh
zig build test -- --test-filter "layout builder"
zig build test -- --test-filter "plan-native contract conformance matrix optional"
zig build run-typed-program-plan
zig build run-plan-native-optional
zig fmt --check build.zig src examples test bench
zig build lint -- --max-warnings 0
zig build test --summary all
git diff --check
```

## Implementation Brief
1. step=add_layout_namespace; owner=implementer; success_criteria=`ability.ir.builder.layout.finish*` flattens nested specs and returns validated `ProgramPlan`.
2. step=add_focused_layout_tests; owner=implementer; success_criteria=scalar/product/sum/extract/choice/output cases pass and inspect computed spans.
3. step=add_contract_assertions; owner=implementer; success_criteria=requested `Program.contract` fields match expected metadata for layout-built plans.
4. step=rewrite_required_examples; owner=implementer; success_criteria=current stdout remains stable for `run-typed-program-plan` and `run-plan-native-optional`.
5. step=attempt_typed_helper_port; owner=implementer; success_criteria=all five helpers use layout without signature changes, or raw implementation remains with PR-body follow-up.
6. step=update_docs; owner=implementer; success_criteria=docs state raw tables remain, layout computes spans, emits same ProgramPlan, and is not parser/compiler/VM/Artifact/second IR.
7. step=run_closure_proof; owner=implementer; success_criteria=`zig fmt --check build.zig src examples test bench`, focused tests, example runs, `zig build lint -- --max-warnings 0`, `zig build test --summary all`, and `git diff --check` pass.
8. step=ship_pr; owner=implementer; success_criteria=branch is pushed and a PR is opened with proof summary after all gates pass.
