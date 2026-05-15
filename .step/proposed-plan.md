Iteration: 7

# Capability-Routed Effect Exchange Implementation Plan

## Summary
Build capability-routed Effect Exchange by extending the existing nested `Program.Exchange` surface with provider manifests, capability grants, deterministic attenuation, route witnesses, routing catalogs, response authorization metadata, mailbox integration, and journal event records. First wave is the pure data/validation layer under `Program.Exchange`; completion requires both new examples to run and the full requested Zig proof bundle to pass without public-root widening or `Program.Session` semantic changes.

Chosen strategy: keep Ability as a typed validation/calculus layer, not a transport, security, async, or broker layer. Hosts still own identity, signing, encryption, transport, storage, scheduling, persistence, and provider execution.

## Non-Goals/Out of Scope
No cryptographic authentication, security claims, network stack, async runtime, broker, persistence backend, RPC framework, LLM/tool integration, scheduler, parser/source language, public VM API, Artifact API, public-root widening, `ProgramValue` widening, serializable request tokens, cross-thread sessions, arbitrary host serialization, host context serialization, or allocator/thread serialization.

## Interfaces/Types/APIs Impacted
- `Program` constants: add `exchange_provider_format_version = 1`, `exchange_provider_fingerprint_version = 1`, `exchange_capability_format_version = 1`, `exchange_capability_fingerprint_version = 1`, `exchange_authorization_fingerprint_version = 1`, `exchange_route_fingerprint_version = 1`; mirror aliases under `Program.Exchange`.
- `Program.Exchange.ProviderManifest`: deterministic encode/decode, `fingerprint`, provider label, supported manifest fingerprints, protocol labels, operation/after sites, protocol op fingerprints, response kinds, byte/capsule limits, tags, metadata bytes.
- `Program.Exchange.Capability`: deterministic encode/decode, `fingerprint`, issuer, subject provider fingerprint, manifest fingerprint, request-kind/site/protocol/program/response/ref/byte/capsule scopes, logical generation expiry, parent fingerprint, attenuation path fingerprint.
- `Program.Exchange.Authorization`: separate metadata sidecar, not part of core `ResponseEnvelope.bytes`; fields include provider/capability/path/route/request/response fingerprints and `authorization_fingerprint`.
- `Program.Exchange.Route` and `Program.Exchange.Router`: deterministic route witnesses and runtime-data catalog selection with no-route, one-route, ambiguous, and blocked results.
- `Program.Exchange.Policy`, `MailboxRunner`, and `Session.Journal`: add route/auth constraints, routed outbox support, response authorization checks, and optional skippable exchange ledger events.

## Implementation Brief
1. step=constants-and-helpers; owner=implementation; success_criteria=new version aliases, deterministic set/limit/blocker/fingerprint helpers compile and existing exchange tests still pass.
2. step=provider-manifest; owner=implementation; success_criteria=provider manifest encode/decode/support/malformed tests pass.
3. step=capability-and-attenuation; owner=implementation; success_criteria=grant, request validation, structured blockers, and broadening-failure tests pass.
4. step=response-authorization; owner=implementation; success_criteria=authorization sidecar encode/decode, valid auth pass, missing/wrong auth reject, existing response fingerprint tests unchanged.
5. step=route-and-router; owner=implementation; success_criteria=single/no/ambiguous/blocker/priority and duplicate-op route tests pass.
6. step=policy-mailbox-journal; owner=implementation; success_criteria=routed outbox, authorized apply, unauthorized reject, journal event encode/decode/replay tests pass.
7. step=examples-docs-build; owner=implementation; success_criteria=new examples and run steps work, docs updated, path/lint manifest updated if required.
8. step=closure-proof-and-ship; owner=implementation; success_criteria=all proof commands from the spec pass, durable proof is recorded, branch is pushed, and PR is opened with proof summary.

## Proof Commands
```bash
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-effect-capability-routing
zig build run-effect-capability-attenuation
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
zig build test --summary none -- --test-filter "capability"
zig build test --summary none -- --test-filter "provider"
zig build test --summary none -- --test-filter "attenuation"
zig build test --summary none -- --test-filter "route"
zig build test --summary none -- --test-filter "authorization"
zig build test --summary none -- --test-filter "exchange"
zig build test --summary none -- --test-filter "mailbox"
zig build test --summary none -- --test-filter "journal"
zig build test --summary none -- --test-filter "capsule image"
zig build test --summary none -- --test-filter "session"
zig build lint -- --max-warnings 0
```

Iteration: 7
