# Plan-Native Contract Conformance Matrix

## Summary
Create a built-in plan-native contract conformance matrix for the existing
plan-native built-in prototypes. This branch is a conformance/specification
branch for the future built-in migration, not a public API migration branch.

The primary assertion surface is `Program.contract`. The branch must not add
new execution primitives, expose new public root APIs, remove compatibility
built-ins, introduce custom effect authoring, add parser/compiler/VM/artifact
surfaces, or widen `ProgramValue`.

## Acceptance
- Contract tests define the expected plan-native shape for Optional, State,
  Reader, Writer, Exception, and Resource.
- Tests assert requirement labels, lifecycle/output tags, output declarations,
  op names, op modes, payload/resume/result refs, after-hook flags, schema
  declarations, field/variant declarations, nested-with targets where present,
  reachable return errors where present, and executable capability-ledger status.
- Existing plan-native examples still build and run.
- Existing compatibility tests remain green.
- The PR description explains that this is a conformance/specification branch,
  not a public API migration branch.

## Proof
```sh
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build test --summary all
zig build lint -- --max-warnings 0
```

## Additional Example Proof
```sh
zig build run-plan-native-optional
zig build run-plan-native-state-reader
zig build run-plan-native-writer
zig build run-plan-native-exception
zig build run-plan-native-resource
```

## Implementation Brief
1. step=baseline_and_st_sync; owner=engineering; success_criteria=branch is based on latest `main`, durable `$st` tasks are selected, and no unrelated diffs are published.
2. step=add_contract_fixture_harness; owner=engineering; success_criteria=small reusable test helpers compare expected `Program.contract` facts without new public root APIs.
3. step=cover_plan_native_targets; owner=engineering; success_criteria=Optional, State, Reader, Writer, Exception, and Resource contracts assert required labels, lifecycle/output tags, refs, modes, schemas, outputs, after flags, return errors where present, nested targets where present, and executable ledger support.
4. step=wire_test_surface; owner=engineering; success_criteria=the new conformance test is wired into `zig build test` and tracked Zig manifests without changing compatibility built-ins.
5. step=run_focused_and_example_proof; owner=engineering; success_criteria=focused conformance tests and all plan-native example run steps pass.
6. step=run_full_fixed_point_closure; owner=engineering; success_criteria=required fmt, diff, build, test, lint proof gates pass and a one-change challenge finds no material missing change.
7. step=ship_pr; owner=engineering; success_criteria=branch is pushed and a PR is opened with proof and conformance/specification non-migration wording.
