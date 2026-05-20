Iteration: 9

# Canonical Evidence Kernel for Ability

## Summary
Refactor Ability around a canonical `Program.Evidence` substrate for versioned evidence domains, deterministic evidence references, dependency lists, fingerprint construction, blockers, validation reports, certificate/authorization views, journal projections, and policy summaries.

This is a refactor milestone, not a new effect-semantics milestone. Existing behavior, examples, public root exports, encoded formats, and semantic fingerprints must remain stable unless an intentional version bump is made and justified.

## Non-Goals/Out of Scope
Do not add new effect semantics, receipts, membranes, settlement, storage backends, xitdb integration, parser/source language, public VM APIs, Artifact APIs, async runtime, network/LLM integration, persistence backend, cryptographic signing/encryption, legal-contract semantics, distributed consensus, provider execution scheduling, service discovery, public-root widening, `ProgramValue` widening, serializable request tokens, cross-thread sessions, arbitrary host handler serialization, host context serialization, runtime allocator/thread serialization, or broad public-concept renames.

`Program.Session` remains the primitive host-driven defunctionalized execution machine. Request tokens remain in-process misuse guards and are never serialized. Hosts still own identity, signing, encryption, transport, storage, scheduling, network, persistence, provider lifecycle, provider execution, and cancellation side effects.

## Interfaces/Types/APIs Impacted
- Add `Program.Evidence`, preferably backed by `src/program/evidence.zig`; do not widen the public root.
- Keep existing public version constants available and source-compatible; make them delegate to Evidence domains where practical.
- Add Evidence domain registry entries for current version/fingerprint families across ProgramPlan, Session, Capsule, Journal, Exchange, Capability, Linear Session, Treaty, ProviderHarness, Morphism, Residualization, Pipeline, and provider-side derived evidence.
- Add `Evidence.Ref`, `Evidence.DependencyGraph`, `Evidence.FingerprintBuilder`, `Evidence.Blocker`, `Evidence.Report`, `Evidence.CertificateView`, `Evidence.AuthorizationView`, `Evidence.JournalProjection`, `Evidence.PolicySummary`, and object-shape helpers.
- Add adapters first. Existing typed subsystem APIs remain authoritative and source-compatible while exposing `.evidenceRef()`, `.toEvidenceBlocker()`, `.toEvidenceReport()`, `.evidenceView()`, or equivalent helpers where useful.
- Add documentation: README note, `docs/program_plan.md` Evidence/validation section, `docs/custom_effect_authoring.md` note, and authoritative `docs/evidence_kernel.md`.
- Add focused evidence tests, preferably in `test/evidence_kernel_test.zig`, and wire into build/test manifests as needed.

## Implementation Brief
1. step=evidence_inventory_and_domain_registry; owner=implementation; success_criteria=add Evidence domains doc/table and `Program.Evidence.Domain` registry covering all known format/fingerprint domains, including ProviderHarness derived/provider-side domains; existing version constants match registry; duplicate ids/names rejected; durable byte domains carry format versions; journal v4 and request envelope v3 are represented; no behavior changes.
2. step=evidence_refs_dependencies_builder; owner=implementation; success_criteria=add deterministic `Evidence.Ref` helpers, dependency roles/list/fingerprint/lookup/duplicate checks, and `FingerprintBuilder` with explicit domain/version, stable fields, fixed-endian scalars, nested refs, optionals, and no pointer/token APIs; migrated high-risk builders preserve existing fingerprints.
3. step=evidence_blockers_reports_views; owner=implementation; success_criteria=add shared `Evidence.Blocker`, `Evidence.Report`, `Evidence.CertificateView`, `Evidence.AuthorizationView`, `Evidence.PolicySummary`, and compile-time shape helpers; subsystem blockers and validators can lower or adapt without deleting typed APIs; report and view fingerprints/dependencies are stable.
4. step=evidence_journal_projections; owner=implementation; success_criteria=add `Evidence.JournalProjection` and projection helpers for ProviderHarness, Treaty, Capability/Route, Obligations, Morphism offers, and provider-side events where possible; preserve journal v4 bytes and legacy v1/v2/v3/v4 decode.
5. step=provider_harness_treaty_evidence_integration; owner=implementation; success_criteria=ProviderHarness and Treaty stacks expose Evidence refs, dependencies, reports, blocker lowering, certificate/authorization views, policy summaries, and journal projections while preserving existing APIs/fingerprints/journal bytes and examples.
6. step=linear_capability_exchange_pipeline_adapters; owner=implementation; success_criteria=Linear Effect Sessions, Capability/Route/Authorization, Exchange envelopes, Journal, Pipeline, Residualization, and Morphism expose Evidence refs/reports/blockers/views/projections as adapters; existing fingerprints, envelope bytes, journal legacy decode, and examples remain stable.
7. step=evidence_docs_architecture_guide; owner=documentation; success_criteria=README, `docs/program_plan.md`, `docs/custom_effect_authoring.md`, and new `docs/evidence_kernel.md` explain domains, refs, dependencies, blockers, reports, certificates/authorizations, journal projections, version-bump policy, request-token boundary, no cryptographic-security claim, and how future maintainers add evidence objects/events/blockers/tests.
8. step=evidence_kernel_tests; owner=verification; success_criteria=add focused tests for registry uniqueness/version parity, refs, dependencies, builder semantics, blocker lowering, reports, certificate/authorization views, journal projections, legacy journal decode, ProviderHarness/Treaty/Capability/Linear/Exchange/Journal/Pipeline/Residualization adapter parity, and unchanged fingerprints.
9. step=fixed_point_review_and_closure; owner=verification; success_criteria=run fixed-point routing preflight, negative-ledger pass, de novo review/challenge loop, one-change challenge, full requested proof suite, record `$st` proof, commit and push only relevant changes, and `$ship` a PR with evidence-kernel summary and proof.

## Proof Commands
```bash
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build test --summary all
zig build test --summary none -- --test-filter "evidence"
zig build test --summary none -- --test-filter "domain"
zig build test --summary none -- --test-filter "fingerprint"
zig build test --summary none -- --test-filter "blocker"
zig build test --summary none -- --test-filter "report"
zig build test --summary none -- --test-filter "certificate"
zig build test --summary none -- --test-filter "authorization"
zig build test --summary none -- --test-filter "journal projection"
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
zig build test --summary none -- --test-filter "pipeline"
zig build test --summary none -- --test-filter "residual"
zig build test --summary none -- --test-filter "morphism"
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
zig build lint -- --max-warnings 0
```
