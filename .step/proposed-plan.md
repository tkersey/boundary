# Typed Program.protocol Implementation Plan

## Summary
Build a typed defunctionalized effect protocol for `Program.Session` by adding
additive `Program.protocol` descriptors, site lookup, typed request/after views,
site-aware response/resume helpers, and compile-time coverage witnesses.

Keep `Program.contract.session` as compatible static metadata and keep
`Program.Session` as the only execution surface. The protocol must not become a
host driver, serializer, VM, or second runtime.

## Non-Goals
- Do not change `Program.run` semantics.
- Do not change `Program.Session` execution semantics.
- Do not remove or rename `Program.contract.session.yield_sites` or
  `Program.contract.session.after_sites`.
- Do not widen the public root.
- Do not expose `effect.Define`, `effect.ops`, generated public custom effects,
  VM APIs, Artifact APIs, parser/compiler/source-language APIs, async runtime,
  network/LLM integration, durable session snapshot/restore, cross-thread
  session resume, serializable request tokens, new value codecs, or widened
  `ProgramValue`.
- Do not bump trace fingerprint version unless fingerprint contents change.
- Do not add automatic host-driver execution in this branch.

## Acceptance
- `Program.protocol.operationSite(label, op_name, occurrence_index)` and
  `Program.protocol.siteByIndex(index)` expose typed operation descriptors.
- `Program.protocol.afterSite(label, op_name, occurrence_index)` and
  `Program.protocol.afterSiteByIndex(index)` expose typed after descriptors.
- Operation descriptors expose static site metadata plus `Payload`, `Resume`,
  `Result`, `payload_ref`, `resume_ref`, `result_ref`, `has_after`,
  `may_resume`, and `may_return_now`.
- After descriptors expose source operation metadata plus `Input`, `Output`,
  `Result`, `input_ref`, `output_ref`, and `result_ref`.
- Dynamic operation and after requests can be checked against static site
  descriptors by site index and fingerprint.
- Typed request/after views expose descriptor-derived payload/current value
  access.
- Site-aware response trace helpers produce the same response fingerprint as raw
  `responseTrace` for valid inputs.
- Typed resume, return-now, and resume-after helpers preserve existing pending
  request token, runtime, lifecycle, and type validation.
- Coverage helpers accept complete site sets and fail at comptime for omitted,
  duplicate, or foreign-program descriptors.
- `examples/agent_loop.zig` uses typed protocol sites where practical and no
  longer dispatches by raw `request.op_name` strings for normal operation flow.
- README and `docs/program_plan.md` document the typed protocol surface and
  unchanged non-goals.

## Proof
```sh
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-agent-loop
zig build test --summary all
zig build test --summary none -- --test-filter "protocol"
zig build test --summary none -- --test-filter "site"
zig build test --summary none -- --test-filter "session"
zig build test --summary none -- --test-filter "trace"
zig build test --summary none -- --test-filter "replay"
zig build test --summary none -- --test-filter "agent"
zig build lint -- --max-warnings 0
```

## Implementation Brief
1. step=baseline_and_surface_map; owner=implementer; success_criteria=confirm latest main, import this typed protocol plan into `$st`, map current `Program.contract.session`, `Program.Session` request/after structs, typed value mapping, response trace helpers, agent_loop, docs, and relevant tests.
2. step=operation_protocol_descriptors; owner=implementer; success_criteria=add `Program.protocol` operation descriptors, `operationSite`, and `siteByIndex` derived from existing session yield sites, with typed `Payload`, `Resume`, and `Result` aliases and no public root widening. (deps: baseline_and_surface_map)
3. step=after_protocol_descriptors; owner=implementer; success_criteria=add after descriptors, `afterSite`, and `afterSiteByIndex` with typed `Input`, `Output`, and `Result` aliases; prove one static input/output pair from existing Session handler/type evidence or abort without changing fingerprints. (deps: operation_protocol_descriptors)
4. step=typed_request_after_views; owner=implementer; success_criteria=add `matches`, `as`, typed payload/value views, and site-aware response trace helpers for operation and after requests, checking site index plus fingerprint and preserving raw response fingerprint parity. (deps: after_protocol_descriptors)
5. step=typed_session_resume_helpers; owner=implementer; success_criteria=add `resumeTyped`, `returnNowTyped`, and `resumeAfterTyped` that delegate to existing Session methods and preserve pending-token, runtime, lifecycle, and type validation. (deps: typed_request_after_views)
6. step=coverage_witness_helpers; owner=implementer; success_criteria=add operation, after, and all-site coverage helpers that fail at comptime for omitted reachable sites, duplicate descriptors, and descriptors from another Program. (deps: typed_session_resume_helpers)
7. step=protocol_tests_and_compile_fail; owner=implementer; success_criteria=focused tests cover operation/after descriptor metadata and types, matching/mismatched dynamic bindings, typed resume/return/after behavior, response trace parity, coverage success/failures, same-op duplicate sites, helper-yield sites, nested-with sites, and existing session/replay/program-run compatibility. (deps: coverage_witness_helpers)
8. step=agent_loop_and_docs; owner=implementer; success_criteria=`examples/agent_loop.zig` dispatches through typed protocol sites, preserves deterministic replay fingerprints, and README/docs describe typed protocol descriptors, dynamic request checks, coverage helpers, explicit host execution, request token boundaries, fingerprint boundaries, and unchanged non-goals. (deps: protocol_tests_and_compile_fail)
9. step=fixed_point_review; owner=implementer; success_criteria=de novo fixed-point review, negative-ledger handoff, and one-change challenge find no unresolved material soundness, invariant, hazard, complexity, or verification gaps. (deps: agent_loop_and_docs)
10. step=full_proof_and_ship; owner=implementer; success_criteria=all requested proof commands pass, branch is pushed, and `$ship` opens a PR summarizing protocol descriptors, typed request/after checks, site-aware response helpers, coverage witnesses, agent_loop changes, fingerprint version status, explicit non-runtime posture, and unchanged non-goals. (deps: fixed_point_review)
