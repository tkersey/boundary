# Program.Session After Continuations Execution Plan

## Summary
Add defunctionalized after-continuation support to `Program.Session` under
`ability.program(...)`. The existing synchronous `Program.run` path remains
unchanged. Session execution should yield operation requests and, on normal
completion with pending after hooks, yield after-continuation requests as
explicit data. Hosts resume operation requests with op resume values and resume
after requests with typed transformed values.

This branch extends the existing pausable session executor. It must not add a
VM, Artifact API, parser, compiler, async runtime, network/LLM integration,
source-language API, public root export, public generated custom effects, or
`ProgramValue` widening.

## Acceptance
- `Program.Session.Step` exposes `.request`, `.after`, and `.done`.
- `Program.Session.AfterRequest` exposes requirement index/label, op index/name,
  current value ref, expected output ref, typed value access, and request
  identity.
- `session.@"resume"(request, value)` remains op-request only.
- `session.resumeAfter(after_request, value)` is after-request only.
- `session.returnNow(request, value)` remains choice/abort terminal completion.
- Transform ops with `has_after=true` yield op request, resume normally, then
  yield after request during normal unwinding, and complete with the transformed
  after value.
- Choice ops with `has_after=true` record after continuations only on resumed
  paths; `returnNow` paths preserve current terminal behavior and skip after
  continuations when `Program.run` does.
- Multiple after continuations yield in the same reverse order as `Program.run`.
- Helper calls preserve frame behavior when after hooks unwind during helper
  completion and resume into the caller.
- Nested-with after hooks are supported if feasible; otherwise the remaining
  unsupported shape has a precise blocker, contract coverage, and docs.
- Scalar, product, and sum after values use existing `Body.value_schema_types`
  machinery; `ProgramValue` remains scalar.
- `Program.contract.session` no longer reports a blanket `after_hook` blocker
  for supported after plans.
- Wrong type, stale request, wrong session, wrong API kind, pending `next`, and
  post-done interaction fail cleanly.
- Result/output cleanup obligations match `Program.run`.
- `examples/agent_loop.zig` remains deterministic and network-free; update it
  for after continuations only if clarity improves.
- README and `docs/program_plan.md` document operation requests, after requests,
  host after resumption, reverse ordering, terminal bypass behavior, and
  non-goals.

## Non-Goals
- Do not change `Program.run` semantics.
- Do not expose `effect.Define`, `effect.ops`, generated custom effects, a VM,
  Artifact APIs, parser, compiler, source-language APIs, async runtime, network,
  or LLM integration.
- Do not widen the public root or `ability.ir.ProgramValue`.
- Do not add session snapshot/restore or durable persistence in this branch.

## Proof
```sh
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-agent-loop
zig build test --summary all
zig build test --summary none -- --test-filter "session"
zig build test --summary none -- --test-filter "after"
zig build test --summary none -- --test-filter "agent"
zig build test --summary none -- --test-filter "program"
zig build lint -- --max-warnings 0
```

## Implementation Brief
1. step=baseline_guard; owner=implementer; success_criteria=confirm latest `main`, run focused current session/agent smoke, import this plan into `$st`, and note obsolete after-hook blocker tests.
2. step=session_core_state; owner=implementer; success_criteria=`ExecutableSessionForPlan` has tagged pending op/after state, nonzero after-stack capacity when needed, and pausable normal-completion after unwinding. (deps: baseline_guard)
3. step=after_request_api; owner=implementer; success_criteria=`Program.Session` exposes `.after`, `AfterRequest.value(T)`, and `resumeAfter`, with kind/session/token/ref validation and op API separation. (deps: session_core_state)
4. step=after_unwind_semantics; owner=implementer; success_criteria=transform/choice resumed paths yield after continuations in reverse order, while returnNow and abort terminal paths bypass after continuations. (deps: after_request_api)
5. step=helper_nested_with; owner=implementer; success_criteria=helper-after and nested-with-after behavior is supported with tests, or any nested-with residual has a precise blocker, contract coverage, and docs. (deps: after_unwind_semantics)
6. step=contract_and_cleanup; owner=implementer; success_criteria=session contract removes blanket `after_hook` blocker for supported after plans, obsolete compile-fail coverage is removed or narrowed, and result/output cleanup tests pass after host-driven after continuations. (deps: after_unwind_semantics, helper_nested_with)
7. step=session_after_tests; owner=implementer; success_criteria=focused tests cover transform after, choice after resumed path, choice returnNow bypass, reverse order, helper after, nested-with after or precise blocker, product after, sum after, wrong typed after resume, stale/mismatched identity, and Program.run parity. (deps: contract_and_cleanup)
8. step=docs_and_optional_example; owner=implementer; success_criteria=README and `docs/program_plan.md` document the new session after surface and non-goals; `agent_loop` is updated only if the deterministic main loop remains clearer. (deps: session_after_tests)
9. step=fixed_point_review; owner=implementer; success_criteria=de novo review, one-change challenge, and remediation loop find no unresolved material soundness, invariant, hazard, complexity, or verification gaps. (deps: docs_and_optional_example)
10. step=full_proof_and_ship; owner=implementer; success_criteria=all proof commands pass, branch is pushed, and `$ship` opens a PR with concise proof and non-goal confirmations. (deps: fixed_point_review)
