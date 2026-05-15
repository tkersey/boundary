Iteration: 3
# Effect Exchange ABI Implementation Plan

## Summary
Add a transport-neutral Effect Exchange ABI under the existing `Program` namespace. The exchange surface must make a compiled program's effect protocol manifest, yielded operation/after requests, host responses, continuation capsule images, and journal references exchangeable as deterministic typed data without adding transport, async, network, persistence, scheduler, VM, source-language, Artifact, or request-token serialization responsibilities.

The implementation is additive:
- Keep public root exports unchanged: `ability.effect`, `ability.ir`, `ability.program`, and `ability.Runtime`.
- Add version constants for exchange manifest/request/response formats and fingerprints.
- Add `Program.Exchange.Manifest`, `Program.Exchange.RequestEnvelope`, `Program.Exchange.ResponseEnvelope`, `Program.Exchange.Policy`, `Program.Exchange.MailboxRunner`, response-apply helpers, and capsule restore helpers.
- Reuse existing `Program.contract`, `Program.protocol`, `Program.Session`, `Program.Session.Capsule.Image`, and `Program.Session.Journal` as the authority for sites, schemas, parked execution, continuation images, and durable interaction logs.
- Preserve all existing version domains unless their bytes actually change.

## Execution Waves
1. Baseline and byte authority: confirm latest main, recall local constraints, add exchange version constants, and factor shared deterministic value-image/envelope byte helpers with fail-closed decode behavior.
2. Manifest and request envelopes: encode/decode program manifests and operation/after request envelopes with typed payload/current value images, schema/site metadata, optional capsule image, policy validation, and stable fingerprints.
3. Response envelopes and resume: encode/decode resume, return_now, and resume_after envelopes; validate them against matching request/manifest/session state; apply through existing typed session paths; restore from embedded capsule images when requested.
4. Mailbox, journal, examples, docs: add nonblocking transport-neutral mailbox runner, exchange-aware journal append helpers, the mailbox/restart examples and build steps, path manifest updates, and Effect Exchange docs.
5. Fixed-point closure and ship: run the requested proof bundle, repair any findings, record durable proof, commit, push, and open a PR with concise proof and API/non-goal summary.

## Non-Goals
- Do not change `Program.run` semantics or primitive `Program.Session` stepping semantics.
- Do not remove manual Session, Capsule, Journal, Handler, Interpreter, Morphism, Residualize, or Pipeline APIs.
- Do not add parser/source language, VM APIs, Artifact APIs, async runtime, network/LLM integration, persistence backend, message broker, scheduler, public root widening, or `ProgramValue` widening.
- Do not serialize request tokens, arbitrary host handlers, host context, allocator/runtime/thread state, or cross-thread sessions.
- Do not claim cryptographic security.

## Version Policy
- Add `Program.exchange_manifest_format_version = 1`.
- Add `Program.exchange_manifest_fingerprint_version = 1`.
- Add `Program.exchange_request_format_version = 1`.
- Add `Program.exchange_request_fingerprint_version = 1`.
- Add `Program.exchange_response_format_version = 1`.
- Add `Program.exchange_response_fingerprint_version = 1`.
- Leave trace fingerprint version at 2, capsule image format/fingerprint at 1, journal format/fingerprint at 1, reinterpretation fingerprint at 2, residualization fingerprint at 1, and pipeline fingerprint at 1.

## Acceptance
- Manifest images encode/decode, fingerprint stably, include operation/after/value schema metadata, and reject malformed bytes or mismatches.
- Request envelopes encode/decode operation and after yields, include typed payload/current value images and optional capsules, omit request tokens, fingerprint stably, and reject malformed bytes.
- Response envelopes encode/decode resume, return_now, and resume_after, validate expected response kind/ref/value/request/manifest/program-plan compatibility, and reject malformed bytes.
- Applying response envelopes works for parked transform, choice, abort, and after requests; wrong or stale responses fail closed; request tokens remain local.
- A request envelope with embedded capsule image can restore a fresh session and accept a matching response after the original runtime/session is gone.
- Mailbox runner writes one outbox request per parked yield, consumes matching inbox responses, rejects mismatches, respects policy, returns parked without blocking, and returns done when final result is ready.
- Journal integration records request/response/capsule exchange fingerprints while preserving the v1 journal wire format unless a deliberate version change is justified.
- Pipeline/residual programs can expose optional source/residual mapping and manifest pipeline fingerprints when those metadata are available.
- Examples `run-effect-exchange-mailbox` and `run-effect-exchange-restart` demonstrate in-memory outbox/inbox, embedded capsules, restart restore, journal encode/decode/replay, and printed fingerprints without network or async.

## Implementation Brief
- step=baseline and exchange plan sync; owner=lead; success_criteria=`git status`, `git rev-parse`, `zig version`, `$st` projection, and negative-ledger/learnings recall establish the current baseline before edits.
- step=add byte authority and versions; owner=core implementer; success_criteria=exchange version constants and shared deterministic envelope/value-image helpers compile and fail closed for corrupt bytes.
- step=add manifest/request envelopes; owner=core implementer; success_criteria=manifest and request image APIs validate against `Program.contract`/`Program.protocol`, include schema/site metadata and optional capsule bytes, and omit request tokens.
- step=add response/apply/restore APIs; owner=core implementer; success_criteria=response envelopes validate expected refs/kinds and resume or restore sessions through existing typed paths.
- step=add mailbox/journal/policy integration; owner=integration implementer; success_criteria=mailbox runner is nonblocking/transport-neutral, policy guards enforce allow-lists and sizes, and journal append helpers reference exchange fingerprints.
- step=add examples/docs/build manifests; owner=examples/docs implementer; success_criteria=mailbox and restart examples, build steps, repo path manifest, README, `docs/program_plan.md`, and `docs/custom_effect_authoring.md` describe the ABI and non-goals.
- step=run fixed-point proof and ship; owner=lead; success_criteria=all requested fmt, diff, build, example, full-test, filtered-test, and lint commands pass; PR contains proof plus API/non-goal summary.

## Proof Commands
```bash
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-effect-exchange-mailbox
zig build run-effect-exchange-restart
zig build run-durable-capsule-replay
zig build run-journal-replay
zig build run-effect-pipeline
zig build run-residualized-approval-policy
zig build run-protocol-reinterpretation
zig build run-interpreter-branching
zig build run-continuation-branching
zig build run-custom-approval-workflow
zig build run-agent-loop
zig build run-typed-program-plan
zig build test --summary all
zig build test --summary none -- --test-filter "exchange"
zig build test --summary none -- --test-filter "manifest"
zig build test --summary none -- --test-filter "envelope"
zig build test --summary none -- --test-filter "mailbox"
zig build test --summary none -- --test-filter "journal"
zig build test --summary none -- --test-filter "capsule image"
zig build test --summary none -- --test-filter "replay"
zig build test --summary none -- --test-filter "pipeline"
zig build test --summary none -- --test-filter "session"
zig build lint -- --max-warnings 0
```
