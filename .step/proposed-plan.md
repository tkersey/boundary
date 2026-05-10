# Program.Session Trace And Fingerprint Execution Plan

## Summary
Add deterministic audit and replay-verification metadata to
`Program.Session` without changing `Program.run` or adding durable
snapshot/restore. Session operation requests and after-continuation requests
should expose read-only trace views, stable request fingerprints, and response
trace helpers that hosts can record across fresh deterministic runs.

The branch must stay additive: no VM, Artifact API, parser, compiler,
source-language API, async runtime, network/LLM integration, public root
widening, `ProgramValue` widening, new value codecs, cross-thread resume, or
request-token serialization.

## Acceptance
- Operation requests expose trace metadata for program label, plan hash, turn,
  request kind, requirement/op identity, mode, payload/resume/result refs,
  payload value fingerprint, after flag, and stable request fingerprint.
- After requests expose equivalent trace metadata for original op identity,
  current value ref/fingerprint, expected output ref, result ref, and stable
  request fingerprint.
- Trace views are read-only metadata and do not expose mutable interpreter
  internals.
- Response trace helpers expose matching request fingerprint, response kind,
  response ref, response value fingerprint, and stable response fingerprint for
  resume, return_now, and resume_after responses.
- Request fingerprints are deterministic across fresh runs when plan, entry
  args, host responses, and execution path match.
- Request fingerprints change when yielded op, payload/current value, or plan
  label/hash changes.
- Response fingerprints change when response kind or response value changes.
- Value fingerprinting covers unit, bool, i32, usize, string contents,
  string-list contents where currently executable, product values, and sum
  values through `Body.value_schema_types`.
- Product hashing includes schema identity, field names, field refs, and field
  value fingerprints.
- Sum hashing includes schema identity, variant name/ordinal/ref, and payload
  fingerprint when present.
- Replay helpers let a host assert that the next yielded request matches a
  previously recorded fingerprint and fail cleanly on mismatch.
- `examples/agent_loop.zig` still demonstrates deterministic decide/tool/final
  execution and now prints request/response trace fingerprints plus a compact
  replay verification pass.
- `Program.contract.session` adds only useful trace capability flags.
- README and `docs/program_plan.md` document trace/fingerprint semantics,
  request tokens versus durable fingerprints, response audit metadata, replay
  verification, host-owned persistence, and non-goals.

## Non-Goals
- Do not change `Program.run` semantics.
- Do not change request or after execution semantics.
- Do not expose `effect.Define`, `effect.ops`, public generated custom effects,
  a VM, Artifact APIs, parser/compiler/source-language APIs, async runtime,
  network/LLM integration, or a widened public root.
- Do not widen `ProgramValue` or add new value codecs.
- Do not add durable session snapshot/restore.
- Do not add cross-thread session resume.
- Do not make request tokens serializable.
- Do not require a particular trace serialization format.

## Proof
```sh
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-agent-loop
zig build test --summary all
zig build test --summary none -- --test-filter "session"
zig build test --summary none -- --test-filter "trace"
zig build test --summary none -- --test-filter "fingerprint"
zig build test --summary none -- --test-filter "replay"
zig build test --summary none -- --test-filter "agent"
zig build lint -- --max-warnings 0
```

## Implementation Brief
1. step=baseline_and_surface_map; owner=implementer; success_criteria=confirm latest main, import this trace plan into `$st`, map current Program.Session request/after structs, typed value storage, plan hash access, agent_loop, docs, and relevant tests.
2. step=request_after_trace_api; owner=implementer; success_criteria=`Program.Session` request and after values expose read-only trace/fingerprint APIs with deterministic turn indexes, program label, plan hash, op/requirement metadata, refs, and value fingerprints. (deps: baseline_and_surface_map)
3. step=response_trace_and_replay_api; owner=implementer; success_criteria=request/after response trace helpers compute response kind/ref/value/request fingerprints, validate response kind/ref/type boundaries, and replay helpers accept matching and reject mismatched request fingerprints. (deps: request_after_trace_api)
4. step=value_fingerprint_structured; owner=implementer; success_criteria=value fingerprinting supports unit, bool, i32, usize, string contents, string-list contents where executable, product values, and sum values through `Body.value_schema_types` with schema-guided field/variant sensitivity and fail-closed unsupported boundaries. (deps: response_trace_and_replay_api)
5. step=trace_tests; owner=implementer; success_criteria=focused tests cover op trace metadata, after trace metadata, stable request fingerprints, payload/current changes, response value/kind changes, string content hashing, product and sum sensitivity, helper-yield stability, replay accept/reject, and parked runtime balance. (deps: value_fingerprint_structured)
6. step=agent_loop_trace_replay; owner=implementer; success_criteria=`examples/agent_loop.zig` prints deterministic request/response trace metadata and demonstrates a first-run record plus second-run replay verification without network/LLM APIs. (deps: trace_tests)
7. step=contract_and_docs; owner=implementer; success_criteria=`Program.contract.session`, README, and `docs/program_plan.md` document trace capability flags, stable request/response fingerprints, request tokens as in-process guards, host-owned persistence, no serialization format, no snapshot/restore, and unchanged non-goals. (deps: agent_loop_trace_replay)
8. step=fixed_point_review; owner=implementer; success_criteria=de novo fixed-point review and one-change challenge find no unresolved material soundness, invariant, hazard, complexity, or verification gaps. (deps: contract_and_docs)
9. step=full_proof_and_ship; owner=implementer; success_criteria=all requested proof commands pass, branch is pushed, and `$ship` opens a PR summarizing trace views, request/response fingerprint contents, value fingerprinting, replay verification, agent_loop demo, request-token boundary, and non-goals. (deps: fixed_point_review)
