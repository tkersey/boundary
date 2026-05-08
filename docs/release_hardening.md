# Release hardening

This repository keeps the public root small while ProgramPlan becomes the single
semantic execution kernel. Release checks should protect that boundary and make
new files visible to package and lint coverage.

## Maintained proof commands

Run these before publishing a branch:

```sh
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build test --summary all
zig build lint -- --max-warnings 0
```

`zig build lint` reads `repo_zig_paths.txt` and also checks that every `.zig`
file under `src`, `examples`, `test`, and `bench` appears in that manifest. Add
new Zig files to the manifest in the same patch that adds the file.

`build.zig.zon` packages the maintained source, docs, examples, tests,
benchmarks, and manifest. Keep package paths aligned with any new top-level
surface that users need in source distributions.

## File classification

Public:

- `src/root.zig`
- `src/ability_shared.zig`
- `src/effect/root.zig`
- `src/ir_api.zig`
- `src/program_api.zig`
- `src/lowered_machine.zig` through the public `ability.Runtime` alias

Public-adjacent:

- `src/effect/*.zig`
- `src/effect_schema.zig`
- `src/internal/program_plan.zig`
- `src/internal_kernel.zig`
- `src/internal_program_plan.zig`
- `examples/*.zig`
- `docs/*.md`
- `README.md`

Internal active:

- `src/internal/*.zig`
- `src/private_modules/*.zig`
- `src/effect_ir.zig`
- `src/frontend.zig`
- `src/interpreter.zig`
- `src/lowering_api.zig`
- `src/program_frontend.zig`
- `src/portable_core.zig`
- `src/reference_eval.zig`
- `src/reference_machine.zig`
- `src/parity_*.zig`
- `src/runtime_contract_registry.zig`
- `src/witnesses.zig`

Compatibility:

- `src/effect/optional.zig`
- `src/effect/state.zig`
- `src/effect/reader.zig`
- `src/effect/writer.zig`
- `src/effect/exception.zig`
- `src/effect/resource.zig`
- `src/effect/generated_family.zig`
- `src/effect/define.zig`

Migration-only:

- `examples/plan_native_optional.zig`
- `examples/plan_native_state_reader.zig`
- `examples/plan_native_writer.zig`
- `examples/plan_native_exception.zig`
- `examples/plan_native_resource.zig`
- `bench/*.zig`

Tests:

- `test/program_api_test.zig`
- `test/public_optional_bound_program_test.zig`
- `test/compile_fail/*.zig`

## Documentation map

- ProgramPlan authoring, typed schemas, tuple args, sum matching, outputs,
  cleanup hooks, nested-with targets, and `Program.contract`:
  `docs/program_plan.md`
- Custom effect authoring direction:
  `docs/custom_effect_authoring.md`
- Release/package/lint discipline and file classification:
  this document

## Built-in effects roadmap

Built-ins stay under `ability.effect` until plan-native replacements have
equivalent examples and tests. Compatibility APIs should remain available while
the plan-native paths prove parity.

Migration order:

1. Optional: typed sum choice/resume/return-now control flow.
2. State and reader: transform operations with final state materialized through
   outputs and reader environment borrowed from handlers.
3. Writer: accumulator output ownership and cleanup.
4. Exception: abort control flow with scalar, product, and sum payloads.
5. Resource: lifecycle behavior, LIFO release, terminal escape, and release
   failure precedence.
6. Custom effect authoring: schema-first helpers that lower to ProgramPlan, once
   built-in semantics have stabilized.

Non-goals for release hardening:

- Do not widen the public root.
- Do not expose Artifact, VM, compile, parser, `effect.Define`, or `effect.ops`
  as public APIs.
- Do not widen `ProgramValue`.
- Do not remove compatibility built-ins until plan-native examples and tests are
  sufficient replacement evidence.
