Iteration: 6

# Program-Backed Provider Harnesses

## Summary
Implement Program-backed ProviderHarness handlers as ordinary Ability Programs, using explicit provider-program step APIs rather than changing `Program.Session`. First wave adds declarations, ProviderOffer v2 for program-backed offers only, request/result mapping, execution state, and synchronous completion. Later waves add nested effect suspension/resume, always-encoded handler capsule images, Evidence/journal integration, examples, docs, and regression proof. Done means all three new examples run, focused provider-program tests pass, existing function-backed ProviderHarness offer fingerprints remain byte-stable, and the full requested Zig proof lane is green or explicitly blocked.

## Non-Goals/Out of Scope
Do not add async runtime, network/RPC server, provider registry, scheduler, service discovery, workflow engine, VM, parser, source language, persistence backend, Artifact API, signing, encryption, security claims, public-root widening, `ProgramValue` widening, serializable request tokens, cross-thread sessions, or arbitrary host handler/context serialization. Do not remove function-backed ProviderHarness handlers or existing Exchange/Treaty/Capability/Journal/Evidence APIs. Do not change `Program.run` or primitive `Program.Session` stepping semantics.

## Interfaces/Types/APIs Impacted
- Add `Program.Exchange.ProviderHandler.program(.{ ... })` for operation and after handlers, with fields: `label`, `op` or `after`, `program`, `map_request`, `map_result`, `usage`, `response_kinds`, `response_use`, `branch_policy`, and optional pure `custom_comptime_mapper`.
- Add request mapping forms: `.payload_to_args`, `.payload_and_metadata_to_args`, `.unit_args`, `.custom_comptime_mapper`.
- Add result mapping forms: `.result_to_resume`, `.result_to_return_now`, `.result_to_resume_after`, `.result_to_outcome_union`.
- Add `ProviderProgramExecution` with deterministic fingerprint, parent request/treaty/provider/offer/route/capability/obligation refs, handler Program label/hash, handler session state, nested turn index, branch id, handler sub-journal, always-encoded capsule image when parked, and Evidence dependencies.
- Add explicit APIs: `ProviderHarness.startProgramExecution(...)`, `ProviderHarness.continueProgramExecution(...)`, and `ProviderHarness.handleNestedResponse(...)`.
- Keep existing `ProviderHarness.handle` for function-backed handlers. If selected offer is program-backed, return a typed blocker such as `handler_program_requires_step_api`.
- Add ProviderOffer v2 only for program-backed offers. V2 includes `provider_program_mapping_fingerprint`; v1 function-backed offer bytes and fingerprints remain unchanged.
- Add version constants: `Program.exchange_provider_program_execution_fingerprint_version = 1`, `Program.exchange_provider_program_mapping_fingerprint_version = 1`, and `Program.exchange_provider_program_nested_request_fingerprint_version = 1`.

## Implementation Brief
1. step=provider_program_declarations_and_offer_v2; owner=implementation; success_criteria=program-backed operation/after declarations derive manifest/catalog entries and ProviderOffer v2 mapping fingerprints while function-backed v1 offers stay byte-stable; duplicate/foreign program mappings reject.
2. step=request_result_mapping_validation; owner=implementation; success_criteria=payload/unit/metadata/custom request mapping and resume/return_now/resume_after/outcome-union result mapping pass focused tests with compile-time failures where possible.
3. step=provider_program_execution_sync_api; owner=implementation; success_criteria=ProviderProgramExecution plus explicit start/continue APIs run synchronous handler Programs through Session and build treaty-bound response packets with execution Evidence refs; legacy handle rejects program-backed offers with a blocker.
4. step=nested_provider_program_suspension_resume; owner=implementation; success_criteria=nested request envelopes include handler capsule images, host-routed treaty-bound ResponseEnvelope resumes handler Sessions, multiple yields work where feasible, and restore checks full linkage.
5. step=evidence_journal_provider_program_integration; owner=implementation; success_criteria=new Evidence domains/version constants, refs, reports, blockers, dependencies, response packet dependencies, handler sub-journal, parent journal projections, and legacy journal decode tests pass.
6. step=program_provider_examples_docs_build; owner=implementation; success_criteria=add `program_provider_direct`, `program_provider_nested`, and `program_provider_resume` examples/build steps; update README, `docs/program_plan.md`, `docs/custom_effect_authoring.md`, and `docs/evidence_kernel.md` with the locked framing and non-goals.
7. step=fixed_point_proof_and_ship; owner=verification; success_criteria=run fixed-point de novo review, negative-ledger handoff, one-change challenge, all requested proof commands, record durable `$st` proof, commit, push, and `$ship` a PR with API/proof/non-goal summary.

## Proof Commands
```bash
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-program-provider-direct
zig build run-program-provider-nested
zig build run-program-provider-resume
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
zig build test --summary none -- --test-filter "program provider"
zig build test --summary none -- --test-filter "provider program"
zig build test --summary none -- --test-filter "nested provider"
zig build test --summary none -- --test-filter "provider harness"
zig build test --summary none -- --test-filter "provider request"
zig build test --summary none -- --test-filter "provider outcome"
zig build test --summary none -- --test-filter "provider journal"
zig build test --summary none -- --test-filter "evidence"
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
zig build lint -- --max-warnings 0
```
