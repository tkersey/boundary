# Defunctionalized Program Session Execution

## Summary
Add an additive `Program.Session` execution surface under
`ability.program(...)` so a host can drive a validated `ProgramPlan` as an
explicit, pausable interpreter. The existing synchronous `Program.run` path must
remain unchanged. The session path yields effect operations as data, accepts
typed host responses, preserves helper/nested-with interpreter frames, and
returns the same result/output cleanup shape as `Program.run`.

This branch is the first defunctionalized execution surface only. It must not
add a VM, Artifact API, parser, compiler, async runtime, network/LLM integration,
source-language API, public root export, or `ProgramValue` widening.

## Acceptance
- `Program.Session.start(runtime, handlers)` begins a runtime-owned pausable
  execution and `session.deinit()` releases unfinished session state.
- `session.next()` yields `.request`, `.done`, or an execution error.
- Requests expose requirement/op metadata, mode, payload/resume refs, payload
  access via typed helpers, and whether the op declares an after hook.
- `.transform` and `.choice` requests resume with values matching the op resume
  ref; `.choice` also supports `returnNow` with a value matching the current
  terminal result ref.
- `.abort` requests complete terminally from a host-supplied result-ref value.
- Helper calls and nested-with frames remain interpreter-owned; yielding inside
  either resumes in the correct explicit frame.
- Typed scalar/product/sum payload and resume values use the existing
  `Body.value_schema_types`; `ProgramValue` remains scalar.
- Wrong resume/result refs or incompatible typed values fail closed.
- Output collection and cleanup match `Program.run`, including result cleanup if
  output collection fails after a result is produced.
- Reachable `has_after` plans fail closed for `Program.Session` with precise
  `UnsupportedSessionAfterHook` compile-time wording.
- `Program.contract.session` exposes minimal support/blocker metadata without
  exposing mutable `ProgramPlan` internals.
- `examples/agent_loop.zig` plus `zig build run-agent-loop` demonstrate a
  deterministic host-driven agent loop using yielded operations as data.
- README and `docs/program_plan.md` document synchronous run vs host-driven
  session execution, non-goals, typed value handling, cleanup rules, and future
  persistence direction.

## Non-Goals
- Do not remove or weaken `Program.run`.
- Do not expose `effect.Define`, `effect.ops`, generated custom effects, a VM,
  Artifact APIs, parser, compiler, source-language APIs, async runtime, network,
  or LLM integration.
- Do not widen the public root or `ability.ir.ProgramValue`.
- Do not make session state serialization mandatory in this branch.
- Do not implement defunctionalized after hooks in v1; fail closed instead.

## Proof
```sh
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-agent-loop
zig build test --summary all
zig build test --summary none -- --test-filter "session"
zig build test --summary none -- --test-filter "agent"
zig build test --summary none -- --test-filter "program"
zig build lint -- --max-warnings 0
```

## Implementation Brief
1. step=map_executor_and_value_surfaces; owner=implementer; success_criteria=entrypoints, interpreter frame model, typed value encode/decode, output cleanup, contract projection, examples, and tests are mapped with concrete file targets before edits.
2. step=add_session_core_api; owner=implementer; success_criteria=`Program.Session` exposes start/next/resume/returnNow/deinit, yields transform/choice/abort request metadata and typed payload accessors, rejects after-hook plans, and leaves `Program.run` unchanged. (deps: map_executor_and_value_surfaces)
3. step=preserve_frames_and_cleanup; owner=implementer; success_criteria=session execution preserves helper/nested-with frames, runtime busy lifecycle, terminal result/output cleanup, and fail-closed mismatch behavior. (deps: add_session_core_api)
4. step=add_session_tests; owner=implementer; success_criteria=focused tests cover transform, choice resume, choice returnNow, abort, helper yield, nested-with yield, wrong ref/type rejection, output cleanup, result cleanup on output failure, and after-hook compile-fail. (deps: preserve_frames_and_cleanup)
5. step=add_agent_loop_example; owner=implementer; success_criteria=`examples/agent_loop.zig` and `zig build run-agent-loop` demonstrate deterministic host-driven decide/tool/final looping through `Program.Session`. (deps: preserve_frames_and_cleanup)
6. step=update_session_docs; owner=implementer; success_criteria=`README.md` and `docs/program_plan.md` explain defunctionalized session execution, cleanup, typed values, non-goals, and future snapshot/restore direction. (deps: add_session_core_api, add_agent_loop_example)
7. step=run_fixed_point_review; owner=implementer; success_criteria=de novo review, one-change challenge, and remediation loop find no unresolved material soundness, invariant, hazard, complexity, or verification gaps. (deps: add_session_tests, add_agent_loop_example, update_session_docs)
8. step=run_full_proof_and_ship; owner=implementer; success_criteria=all requested proof commands pass, branch is pushed, and `$ship` opens a PR with session API, yielded operation, typed value, after-hook limitation, agent example, `Program.run` preservation, and non-goal confirmations. (deps: run_fixed_point_review)
