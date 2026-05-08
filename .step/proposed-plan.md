Iteration: 7

# Branch 2: `Program.contract` Projection

## Round Delta
- Refines the earlier Branch 2 idea into a narrow restore: `Program.contract` only, no `ProgramContractV1`, no new root export.
- Locks the projection as derived compile-time metadata from `Body.compiled_plan`, `Body.value_schema_types`, and `Body.nested_with_targets`.
- Adds the governing safety rule: contract view must never become a second execution authority.

## Summary
Implement Branch 2 from latest `main` (`4b656f0`, verified against `origin/main`): add `ability.program(...).contract` as a read-only compile-time projection for tests and users to inspect executable ProgramPlan metadata. First wave is `src/program_api.zig` only plus focused `test/program_api_test.zig` cases; completion requires scalar/product/sum/output/nested-with/op metadata assertions and full Zig proof gates.

## Non-Goals/Out of Scope
- No new public root exports, serialization format, ArtifactV1, VM, parser, compile API, or custom-effect authoring.
- No built-in effect migration and no higher-level builder changes in this branch.
- No exposure of raw `ProgramPlan.functions`, instruction tables, mutable slices, or execution internals through `contract`.

## Interfaces/Types/APIs Impacted
- Add `pub const contract` inside the type returned by `ability.program(label, Handlers, Body)`.
- Shape: `Program.contract` is a comptime/read-only namespace or zero-sized value with const fields:
  - `label`
  - `Result` and `result_ref`
  - `has_typed_result_schema`
  - `Outputs`
  - `outputs: []const OutputView`
  - `requirements: []const RequirementView`
  - `ops: []const OpView`
  - `nested_with_targets_declared`
  - `executable: ExecutableView`
- Views expose derived fields only: labels, codecs, schema refs, op modes, payload/resume refs, `has_after`, lifecycle/output tags, ledger blocker count/truncation/cap.
- `Program.compiled_plan` remains available; `Program.contract` must not wrap or replace execution.

## Data Flow
`Body.compiled_plan` -> existing validation -> `ProgramContractFor(...)` derives const arrays and type aliases -> user/test reads `Program.contract.*`; runtime execution remains `Program.run(...) -> lowering_api interpreter`.

## Edge Cases/Failure Modes
- Unsupported plans still fail at `ability.program` construction before a usable contract exists.
- Duplicate op names remain distinguishable by requirement label/index in `OpView`.
- Typed result type is exposed as `Program.contract.Result`; product/sum schema refs must match `Body.value_schema_types`.
- Empty outputs use an empty const slice and `Outputs == void`.
- Nested-with reports declaration presence only, not global discovery.

## Tests/Acceptance
- Scalar plan: label, result ref, `Result`, no outputs, executable blocker count 0.
- Product result plan: product codec/schema ref and `Result == Payload`.
- Sum result plan: add or reuse a small sum fixture; assert sum codec/schema ref and `Result == Choice`.
- Outputs plan: output label/codec/schema ref and `Outputs` type.
- Nested-with plan: `nested_with_targets_declared == true`.
- Transform/choice/abort ops: op mode, payload/resume refs, requirement label, `has_after`.
- Negative guard: `contract` does not expose raw `functions`, `instructions`, Artifact, VM, or serialization surfaces.

## Requirement-to-Test Traceability
- Stable projection -> scalar/product/sum/output/nested/op tests in `test/program_api_test.zig`.
- Read-only/no internals -> negative `@hasDecl` assertions.
- No second authority -> tests compare contract fields to `compiled_plan`-derived refs, then still execute `Program.run`.

## Rollout/Monitoring
- Keep branch narrow and publish as one PR after local closure.
- Update README Program section with a short inspection example and explicit “metadata, not execution authority” wording.
- If review challenges abstraction growth, point to no root export, no `ProgramContractV1`, and derived-only implementation.

## Rollback/Abort Criteria
- Revert the branch if `Program.contract` requires public root growth, raw plan-table exposure, duplicated validation logic, or weakens `Program.run` validation.
- Abort implementation if Zig comptime type exposure forces an unstable API; fallback is `result_type_name` plus typed tests deferred to a later design.

## Assumptions/Defaults
- baseline=current local and remote `main` at `4b656f0`; confidence=high; verification_plan=rerun `git ls-remote origin refs/heads/main` before implementation if time passes.
- Branch 1 lands first; confidence=medium; verification_plan=rebase/read `program_api.zig` before editing.
- Projection is compile-time only; confidence=high; verification_plan=unit tests using `comptime` assertions.

## Decision Log
- D1: Add `Program.contract`, not `ability.contract` or `ProgramContractV1`.
- D2: Derive contract from validated ProgramPlan and body hooks; do not store independent contract truth.
- D3: Expose readable descriptors, not raw plan internals.
- D4: Include ledger counts/truncation/cap as executable support summary.

## Implementation Brief
1. step=derive contract view in `src/program_api.zig`; owner=implementer; success_criteria=`Program.contract` exposes requested metadata without new root exports.
2. step=add focused tests in `test/program_api_test.zig`; owner=implementer; success_criteria=all six metadata shapes plus negative internal-surface guards pass.
3. step=update README; owner=implementer; success_criteria=docs show inspection use and distinguish metadata from Artifact/VM/capability maps.
4. step=run proof gates; owner=implementer; success_criteria=`zig version`, focused filters, `zig fmt --check build.zig src examples test bench`, `git diff --check`, `zig build --summary all`, `zig build test --summary all`, and `zig build lint -- --max-warnings 0` pass.
