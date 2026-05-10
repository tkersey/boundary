# Static Session Yield-Site Metadata Implementation Plan

## Summary
Add static session yield-site metadata for `Program.Session` inspectability by
deriving read-only operation and after site catalogs under
`Program.contract.session`, then threading stable site indexes and fingerprints
into dynamic operation and after request traces.

This branch is inspectability-only. It must not change `Program.run` semantics,
request/after execution semantics, public root exports, `ProgramValue`, value
codecs, or add VM, Artifact, parser, compiler, source-language, async runtime,
network/LLM, snapshot/restore, cross-thread resume, serializable request token,
or trace serialization surfaces.

## Acceptance
- `Program.contract.session.yield_sites` exposes reachable operation `call_op`
  sites with stable index, site fingerprint, function/block/instruction
  coordinates, requirement/op metadata, value refs, operation mode, after flag,
  and host capability flags.
- `Program.contract.session.after_sites` exposes one site per reachable
  after-enabled operation call site, tied to the source operation site rather
  than only to `op_index`.
- Dynamic operation traces include operation site index/fingerprint plus
  function/block/instruction coordinates.
- Dynamic after traces include after site index/fingerprint, source operation
  site index, and source function/block/instruction coordinates.
- Request fingerprints include stable site identity and
  `trace_fingerprint_version` is bumped from `1` to `2`.
- Same op and same payload from two different call sites produce distinct site
  indexes, site fingerprints, and request fingerprints.
- Repeated loop yields from the same instruction keep the same static site index
  while dynamic turn indexes differ.
- Helper and explicit nested-with target yields map to their actual reachable
  function coordinates.
- Unreachable `call_op` instructions do not appear in contract session sites.
- `examples/agent_loop.zig` prints compact site-aware request/response trace
  metadata and replay still verifies request fingerprints exactly.
- README and `docs/program_plan.md` document static sites, dynamic site
  back-references, static-vs-dynamic identity, token boundaries, host-owned
  persistence, non-snapshot/non-serialization boundaries, and unchanged
  non-goals.

## Non-Goals
- Do not change `Program.run` semantics.
- Do not change request or after execution semantics.
- Do not remove compatibility built-in APIs.
- Do not expose `effect.Define`, `effect.ops`, public generated custom effects,
  VM APIs, Artifact APIs, parser/compiler/source-language APIs, async runtime,
  network/LLM integration, or a widened public root.
- Do not widen `ProgramValue` or add value codecs.
- Do not add durable session snapshot/restore or cross-thread session resume.
- Do not make request tokens serializable or require a trace serialization
  format.

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
zig build test --summary none -- --test-filter "site"
zig build test --summary none -- --test-filter "replay"
zig build test --summary none -- --test-filter "agent"
zig build lint -- --max-warnings 0
```

## Implementation Brief
1. step=baseline_and_surface_map; owner=implementer; success_criteria=confirm latest main, import this site plan into `$st`, map current `Program.contract.session`, `Program.Session` request/after trace structs, fingerprint hashing, after-stack storage, agent_loop, docs, and relevant tests.
2. step=site_catalog_derivation; owner=implementer; success_criteria=derive deterministic reachable operation and after site catalogs from existing entry reachability, including helper and explicit nested-with target sites, without adding ProgramPlan schema fields or exposing mutable plan tables. (deps: baseline_and_surface_map)
3. step=contract_projection; owner=implementer; success_criteria=expose `Program.contract.session.yield_sites` and `after_sites` with the required operation/after metadata while preserving existing session capability ledger behavior and public-root boundaries. (deps: site_catalog_derivation)
4. step=session_site_trace_threading; owner=implementer; success_criteria=thread operation site identity through request creation, pending request checks, and after-stack entries so operation and after traces expose stable site indexes/fingerprints and source coordinates. (deps: contract_projection)
5. step=fingerprint_v2; owner=implementer; success_criteria=bump trace fingerprint version to `2`, include stable site identity in operation and after request fingerprints, and update all version/fingerprint expectations. (deps: session_site_trace_threading)
6. step=site_trace_tests; owner=implementer; success_criteria=focused tests cover simple transform site metadata, coordinate and requirement/op metadata, dynamic trace site mapping, same-op different-call-site fingerprint disambiguation, deterministic same-site reruns, loop same-site turn changes, helper coordinates, after-site mapping, distinct same-op after sites, unreachable omission, explicit nested-with reachability, and version `2`. (deps: fingerprint_v2)
7. step=agent_loop_and_docs; owner=implementer; success_criteria=`examples/agent_loop.zig` prints turn, operation site index, op name, request fingerprint, and response fingerprint; README and `docs/program_plan.md` document site metadata, token/fingerprint boundaries, replay/audit semantics, and non-goals. (deps: site_trace_tests)
8. step=fixed_point_review; owner=implementer; success_criteria=de novo fixed-point review, negative-ledger handoff, and one-change challenge find no unresolved material soundness, invariant, hazard, complexity, or verification gaps. (deps: agent_loop_and_docs)
9. step=full_proof_and_ship; owner=implementer; success_criteria=all requested proof commands pass, branch is pushed, and `$ship` opens a PR summarizing static site metadata, indexing rules, dynamic trace back-references, fingerprint version bump, same-op/different-site proof, agent_loop demo, request-token boundary, non-snapshot/non-serialization boundary, and unchanged non-goals. (deps: fixed_point_review)
