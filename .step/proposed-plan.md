Iteration: 7

# Effect Treaties Implementation Plan

## Summary
Add Effect Treaties as deterministic, typed, inspectable, proof-carrying agreements over Ability's existing `Program.Exchange`, Capability, Linear Effect Session, Morphism, Pipeline, Capsule, MailboxRunner, and Journal machinery.

Routing finds a provider. A treaty proves the provider may handle this effect in this way.

The implementation is additive under `Program.Exchange`. It preserves `Program.Session` as the primitive host-driven defunctionalized execution machine, preserves the public root (`ability.effect`, `ability.ir`, `ability.program`, `ability.Runtime`), and keeps hosts responsible for identity, signing, encryption, transport, storage, scheduling, network, persistence, provider execution, and cancellation side effects.

## Non-Goals/Out of Scope
Do not change `Program.run` semantics, `Program.Session` primitive stepping semantics, Session/Capsule/Journal/Exchange/Capability/Linear Effect Session/Handler/Interpreter/Morphism/Residualize/Pipeline APIs, the public root, or `ProgramValue`. Do not add a parser/source language, public VM API, Artifact API, async runtime, network or LLM integration, persistence backend, cryptographic signing/encryption, legal-contract semantics, distributed consensus, serializable request tokens, cross-thread sessions, arbitrary host handler serialization, host context serialization, or allocator/thread state serialization.

## Interfaces/Types/APIs Impacted
- `Program` version constants: add provider-offer, morphism-offer, treaty, treaty-certificate, and treaty-authorization format/fingerprint domains without changing trace, request/site/response/value, capsule, journal, exchange envelope, capability, route, linear session, residualization, or pipeline versions unless bytes require it.
- `Program.Exchange.ProviderOffer`: deterministic typed handling claims linked to provider/manifest fingerprints, supported sites/protocol ops, refs, response kinds, usage, response-use, replay, branch, capsule, obligation, size, tag, and metadata policies.
- `Program.Exchange.MorphismOffer`: exchange-facing one-hop protocol adaptation metadata over existing dynamic/residual/pipeline morphism machinery.
- `Program.Exchange.TreatyRequest` and `Program.Exchange.Treaty.Policy`: resolver input and policy constraints for provider selection, adaptation, attenuation, usage, replay, branch, obligation, journaling, response authorization, ambiguity, and byte limits.
- `Program.Exchange.Treaty`: selected agreement with certificate, blockers, direct/dynamic/residualized/pipeline handling mode, source/target correspondence, selected provider offer, capability/attenuation/instance/obligation, route, usage, replay, branch, response-use, obligation transition, journal, and response authorization policy.
- `Program.Exchange.TreatyResolver`: pure/no-IO synthesizer that validates the request, finds direct and one-hop adapted offers, filters capabilities, performs least-authority attenuation when required, validates usage/replay/branch/obligation compatibility, resolves route ambiguity deterministically, and returns treaty/no_treaty/ambiguous/blockers.
- `Program.Exchange` response authorization sidecar: optional treaty-bound metadata with a separate treaty authorization fingerprint domain while preserving existing response envelope fingerprint stability when possible.
- `Program.Exchange.MailboxRunner` and `Program.Session.Journal`: treaty mode, treaty-bound response validation, and treaty journal events while preserving direct routing mode compatibility.
- Examples, tests, docs, `build.zig`, and repo path/lint manifests.

## Implementation Brief
1. step=treaty_core_records; owner=implementation; success_criteria=version constants, ProviderOffer, MorphismOffer, TreatyRequest, Treaty.Policy, Treaty.Blocker, resolver result, deterministic fingerprints, support predicates, byte-limit checks, and malformed-offer checks compile with stable focused tests.
2. step=treaty_certificate_authorization; owner=implementation; success_criteria=Treaty.Certificate and treaty-bound response authorization sidecar bind request/provider/offer/capability/route/morphism/usage/replay/branch/obligation/journal fields, preserve existing response fingerprint behavior, and reject mismatched provider/capability/route/morphism/usage/replay/branch/obligation cases.
3. step=direct_treaty_resolver; owner=implementation; success_criteria=TreatyResolver selects direct provider treaties, rejects no-provider/no-capability/foreign-manifest/ambiguous/default-policy cases, generates least-authority attenuation when required, and returns structured blockers for rejected candidates without IO or provider calls.
4. step=adapted_treaty_resolver; owner=implementation; success_criteria=TreatyResolver supports one-hop dynamic morphism offers, residualized/pipeline adapter metadata when available, residualization preference/fallback policy, max-hop enforcement, source-target ref checks, and handling-mode/source-target correspondence in the treaty certificate.
5. step=mailbox_journal_treaty_mode; owner=implementation; success_criteria=MailboxRunner treaty mode resolves before provider outbox write, sends request plus treaty certificate, journals treaty requested/selected/blocked/certificate/authorization/response accepted/rejected/capability attenuated/obligation events, validates treaty-bound responses, and leaves direct routing mode compatible.
6. step=examples_docs_build; owner=implementation; success_criteria=add `examples/effect_treaty_direct.zig`, `examples/effect_treaty_morphism.zig`, `examples/effect_treaty_replayable.zig`, run steps, repo path/lint manifest updates, README, `docs/program_plan.md`, and `docs/custom_effect_authoring.md` sections explaining Effect Treaties and non-goals.
7. step=fixed_point_proof_and_ship; owner=implementation; success_criteria=run fixed-point de novo review, negative-ledger handoff, one-change challenge, all requested proof commands, record durable `$st` proof, commit, push, and `$ship` a PR with API/proof/non-goal summary.

## Proof Commands
```bash
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
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
zig build test --summary none -- --test-filter "treaty"
zig build test --summary none -- --test-filter "offer"
zig build test --summary none -- --test-filter "resolver"
zig build test --summary none -- --test-filter "morphism offer"
zig build test --summary none -- --test-filter "capability"
zig build test --summary none -- --test-filter "linear"
zig build test --summary none -- --test-filter "obligation"
zig build test --summary none -- --test-filter "exchange"
zig build test --summary none -- --test-filter "journal"
zig build test --summary none -- --test-filter "mailbox"
zig build lint -- --max-warnings 0
```
