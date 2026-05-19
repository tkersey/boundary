Iteration: 8

# Treaty-Bound Provider Harnesses for Effect Exchange

## Summary
Add `Program.Exchange.ProviderHarness`: a typed, deterministic, transport-neutral provider-side executor for treaty-bound request envelopes.

Treaties define the agreement. `ProviderHarness` executes the provider side of that agreement.

The implementation is additive under `Program.Exchange`. It preserves `Program.Session` as the primitive host-driven defunctionalized execution machine, keeps the public root unchanged, keeps `ProgramValue` scalar, and keeps hosts responsible for identity, signing, encryption, transport, storage, scheduling, network, persistence, provider execution, cancellation side effects, and provider lifecycle.

## Non-Goals/Out of Scope
Do not change `Program.run` semantics, `Program.Session` primitive stepping semantics, Session/Capsule/Journal/Exchange/Capability/Linear Effect Session/Treaty/Handler/Interpreter/Morphism/Residualize/Pipeline APIs, the public root, or `ProgramValue`. Do not add a parser/source language, public VM API, Artifact API, async runtime, RPC framework, network server, message broker, provider marketplace, provider registry, service discovery system, agent framework, workflow engine, security/authentication layer, persistence backend, cryptographic signing/encryption, legal-contract semantics, distributed consensus, serializable request tokens, cross-thread sessions, arbitrary host handler serialization, host context serialization, or allocator/thread state serialization.

## Interfaces/Types/APIs Impacted
- `Program` version constants: add `exchange_provider_harness_fingerprint_version = 1` and only bump treaty authorization or journal versions if bytes require it.
- `Program.Exchange.provider(...)`: handler-first declaration helper that derives provider manifest entries, `ProviderOffer` data, offer fingerprints, catalog metadata, typed request views, typed outcome type, and coverage metadata.
- `Program.Exchange.ProviderHarness(config)`: static harness type with `providerManifest`, `providerOffers`, `catalog`, `assertValid`, `assertOffersCovered`, `Request(handler_key)`, `Outcome(handler_key)`, `handle`, `handleNext`, and `drain`.
- `Program.Exchange.ProviderCatalog(.{ HarnessA, HarnessB })`: small static metadata helper for provider manifests, offers, fingerprints, resolver catalog inputs, and duplicate checks.
- `Program.Exchange.ProviderOffer`: remains deterministic data. Preferred path derives it from handler declarations. Manual offers remain an advanced escape hatch only when they exactly match derived handler metadata.
- Typed provider request views: expose provider/offer/treaty/route/capability/usage/branch/replay/obligation/capsule/morphism metadata and typed payload/current-value accessors; do not expose request tokens, runtime pointers, allocator pointers, mutable envelope internals, or host context beyond the explicit provider context argument.
- Provider outcomes: support `resume`, `returnNow`, `resumeAfter`, `reject`, `forward`, `replay`, and optional `pending/noResponse`, with comptime checks where possible and structured blockers otherwise.
- Provider blockers: add structured blocker tags for malformed envelopes, treaty/certificate/provider/offer/capability/route/policy mismatches, decode/capsule/byte-limit failures, handler reject/forward/pending, invalid outcomes, and response build failures.
- Response builder: create response envelopes through existing `ResponseEnvelope` machinery, preserve response envelope fingerprint semantics, and attach treaty-bound authorization.
- Provider-side journal events: add provider manifest/offer derived, request received/validated/rejected, handler invoked, response built/authorized/forwarded, and pending events without bumping journal v4 unless encoding requires v5.
- Examples, tests, docs, `build.zig`, and repo path/lint manifests.

## Implementation Brief
1. step=provider_harness_core_declarations; owner=implementation; success_criteria=add handler-first provider declarations, `ProviderHarness`, derived manifest/offers/fingerprints/catalog metadata, manual-offer exact-match validation, coverage assertions, duplicate/foreign-offer rejection, and stable focused tests.
2. step=provider_request_and_outcomes; owner=implementation; success_criteria=add typed provider request views, typed payload/current-value decode accessors, hidden request-token/runtime/allocator internals, outcome constructors, outcome-policy validation, and tests for valid/invalid request and outcome shapes.
3. step=provider_validation_pipeline; owner=implementation; success_criteria=validate request envelope, treaty certificate, provider/offer, capability/attenuation/route, usage/response-use/replay/branch/obligation/capability-instance, capsule, byte limits, and offer support before invoking handlers, with structured blocker tests.
4. step=response_packet_authorization; owner=implementation; success_criteria=build response envelopes from outcomes, validate them against requests, attach treaty-bound authorization citing provider/offer/treaty/certificate/route/capability/request/response fields, preserve response envelope fingerprint stability, and test unauthorized/mismatched responses.
5. step=provider_journal_mailbox_helpers; owner=implementation; success_criteria=record provider-side journal events, preserve legacy journal decode compatibility, add `handleNext`/`drain` in-memory helpers, and test forward/reject/pending/replay paths.
6. step=round_trip_examples_docs; owner=implementation; success_criteria=add `provider_harness_direct`, `provider_harness_morphism`, and `provider_harness_replayable` examples/build steps; update README, `docs/program_plan.md`, and `docs/custom_effect_authoring.md` with Provider Harnesses framing and non-goals.
7. step=fixed_point_proof_and_ship; owner=implementation; success_criteria=run fixed-point de novo review, negative-ledger handoff, one-change challenge, requested proof commands, record durable `$st` proof, commit, push, and `$ship` a PR with API/proof/non-goal summary.

## Proof Commands
```bash
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-provider-harness-direct
zig build run-provider-harness-morphism
zig build run-provider-harness-replayable
zig build run-effect-treaty-direct
zig build run-effect-treaty-morphism
zig build run-effect-treaty-replayable
zig build run-linear-effect-sessions
zig build run-linear-branch-safety
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
zig build test --summary none -- --test-filter "provider harness"
zig build test --summary none -- --test-filter "provider request"
zig build test --summary none -- --test-filter "provider outcome"
zig build test --summary none -- --test-filter "provider journal"
zig build test --summary none -- --test-filter "derived offer"
zig build test --summary none -- --test-filter "treaty"
zig build test --summary none -- --test-filter "offer"
zig build test --summary none -- --test-filter "resolver"
zig build test --summary none -- --test-filter "capability"
zig build test --summary none -- --test-filter "linear"
zig build test --summary none -- --test-filter "obligation"
zig build test --summary none -- --test-filter "exchange"
zig build test --summary none -- --test-filter "journal"
zig build test --summary none -- --test-filter "mailbox"
zig build lint -- --max-warnings 0
```
