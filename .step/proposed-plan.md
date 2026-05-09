# Built-In Plan-Native State, Reader, and Writer Helpers

## Summary
Build reusable plan-native helper namespaces for state, reader, and writer by
adding small `plan` namespaces inside the existing built-in effect modules,
migrating the state/reader and writer plan-native examples to those helpers plus
`ability.ir.builder.layout`, and proving helper-generated metadata through
`Program.contract`.

The helpers are construction conveniences only. They must emit ordinary
`ProgramPlan` rows, refs, and instructions; delegate row metadata to
`ability.ir.schema.LowerBinding`; keep offsets and schema refs caller-owned; and
leave output materialization in `Body.collectOutputs` / `Body.deinitOutputs`.

## Acceptance
- `ability.effect.state.plan` exposes get/set ordinals, binding/rows helpers,
  state refs/locals, get/set op refs, `callGet`, `callSet`, and final-state
  output metadata helpers.
- `ability.effect.reader.plan` exposes ask ordinal, binding/rows helpers,
  environment refs/locals, ask op refs, and `callAsk`.
- `ability.effect.writer.plan` exposes tell ordinal, binding/rows helpers, item
  refs/locals, tell op refs, `callTell`, and accumulator output metadata helpers.
- Structured product/sum state, environment, and item refs use caller-owned
  explicit `schema_refs`; there is no hidden registry.
- `examples/plan_native_state_reader.zig` and `examples/plan_native_writer.zig`
  use the new helper namespaces and `ability.ir.builder.layout`.
- `test/plan_native_contract_matrix_test.zig` proves helper-generated
  state/reader/writer contract facts through `Program.contract`.
- `docs/program_plan.md` and `docs/release_hardening.md` describe the new
  helpers, output ownership, compatibility APIs, and deferred migrations.

## Non-Goals
- No new ProgramPlan execution instructions or runtime behavior.
- No value codecs or `ProgramValue` widening.
- No public root export widening.
- No exposure of `effect.Define`, `effect.ops`, or public generated custom
  effects.
- No exception/resource migration in this branch.
- No Artifact, VM, compile, parser, compiler, or source-language APIs.
- No hidden global schema registries.
- No removal of compatibility APIs such as `state.handle`, `reader.handle`, or
  `writer.handle`.

## Proof
```sh
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-plan-native-state-reader
zig build run-plan-native-writer
zig build test --summary all
zig build test --summary none -- --test-filter "state"
zig build test --summary none -- --test-filter "reader"
zig build test --summary none -- --test-filter "writer"
zig build test --summary none -- --test-filter "plan-native contract conformance"
zig build lint -- --max-warnings 0
```

## Implementation Brief
1. step=add_state_reader_writer_plan_helpers; owner=implementer; success_criteria=`state.plan`, `reader.plan`, and `writer.plan` expose the required row/ref/local/op/call/output helpers and helper-local tests pass.
2. step=migrate_state_reader_writer_examples; owner=implementer; success_criteria=state/reader and writer examples use helper rows/op refs/calls plus `ability.ir.builder.layout`, with stdout behavior preserved. (deps: st-4013)
3. step=update_contract_matrix_for_helpers; owner=implementer; success_criteria=matrix proves helper-generated state/reader/writer metadata, structured refs, and writer output container ownership. (deps: st-4013)
4. step=update_plan_helper_docs; owner=implementer; success_criteria=`docs/program_plan.md` and `docs/release_hardening.md` describe established helpers and deferred migrations. (deps: st-4014, st-4015)
5. step=run_fixed_point_closure; owner=implementer; success_criteria=fixed-point review, one-change challenge, and all requested proof commands pass with no material findings. (deps: st-4014, st-4015, st-4016)
6. step=ship_plan_helpers_pr; owner=implementer; success_criteria=validated branch is pushed and a PR is opened with helper surface, migrated example, contract fact, compatibility, and non-goal proof summary. (deps: st-4017)
