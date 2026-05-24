Iteration: 7

# Boundary Closure Elaboration Plan

## Summary
Add `Program.BoundaryClosure.Elaboration` as an additive nested namespace that validates a checked closure certificate, compiles supported internal Boundary-native routes into an ordinary residual `ProgramPlan`, lowers explicit WorldPorts to residual effect sites, and emits source/residual/evidence maps plus an elaboration certificate.

The first execution wave builds the namespace, policies, validation, blockers, evidence domains, and certificate skeleton before implementing provider-plan linking. The feature is complete only when the three new examples run, targeted agreement tests pass, and existing closure/provider/treaty/exchange/session/journal/pipeline regressions remain green.

## Non-Goals/Out of Scope
Do not implement World, scheduling, async, storage, transport, network, retries, provider lifecycle, service discovery, parser/source language, public VM APIs, Artifact APIs, signing, encryption, or security claims. Do not change `Program.Session`, `Program.run`, request-token semantics, public root exports, `ProgramValue`, existing value codecs, or cross-thread/session serialization. Do not execute host intrinsic functions during elaboration; host intrinsics may only appear as explicit residual WorldPorts when policy allows.

## Interfaces/Types/APIs Impacted
- Add `Program.BoundaryClosure.Elaboration` with `Input`, `Policy`, `Result`, `Certificate`, `SourceMap`, `EffectRow`, blocker tags, and `NormalFormKind = enum { strict_closed, world_ports_only, partial_with_blockers }`.
- Add version constants on `Program`: `boundary_elaboration_certificate_format_version`, `boundary_elaboration_certificate_fingerprint_version`, `boundary_elaboration_source_map_fingerprint_version`, `boundary_elaboration_effect_row_fingerprint_version`, `boundary_elaboration_trace_map_fingerprint_version`, and `boundary_normal_form_fingerprint_version`, all `= 1`.
- `Input` carries the checked closure certificate, closure graph/report/static treaty plans, root Program, provider harness/provider program bodies, morphism offers, residualization/pipeline adapters, WorldPorts, policy, and optional label/hash override.
- `Result` exposes constants sufficient for `const ElaboratedBody = Result.Body;` or an equivalent Body struct containing `compiled_plan`, `value_schema_types`, `nested_with_targets`, and `site_metadata`.
- Register Evidence domains for elaboration certificate, source map, effect row, trace map, and normal form without widening the public root.

## Implementation Brief
1. step=elaboration_versions_evidence_types; owner=implementation; success_criteria=add elaboration version constants, Evidence domains, blocker tags, policy presets, result/map/effect-row/certificate data structures, and focused evidence-domain tests.
2. step=elaboration_input_validation; owner=implementation; success_criteria=implement `Input.validate` and closure/certificate/ref consistency checks for root, graph, report, policy, provider, provider-program, static plan, and WorldPort mismatches with fail-closed blockers.
3. step=provider_plan_linker; owner=implementation; success_criteria=link supported program-backed provider plans for `payload_to_args`, `unit_args`, `result_to_resume`, `result_to_return_now`, and `result_to_resume_after` only if current ProgramPlan support exists; reject unsupported mappings/schema mismatches deterministically.
4. step=worldport_and_maps; owner=implementation; success_criteria=lower explicit WorldPorts to residual operation sites, preserve source/evidence metadata, and expose source/residual/evidence map helpers.
5. step=morphism_pipeline_normal_form; owner=implementation; success_criteria=integrate supported residualizable morphism, pipeline adapter, and declarative identity/passthrough lowering through existing machinery; add Boundary Normal Form classification and effect-row fingerprints.
6. step=elaboration_examples_docs_tests; owner=implementation; success_criteria=add strict, nested, and world-port elaboration examples/build steps, update README and docs, and add runtime agreement tests.
7. step=fixed_point_proof_and_ship; owner=verification; success_criteria=run fixed-point de novo review, negative-ledger handoff, one-change challenge, full Zig proof suite, record `$st` proof, commit, push, and `$ship` a PR with API/proof/non-goal summary.

## Proof Commands
```bash
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-boundary-elaboration-strict
zig build run-boundary-elaboration-nested
zig build run-boundary-elaboration-world-port
zig build run-boundary-closure-strict
zig build run-boundary-closure-nested
zig build run-boundary-closure-world-port
zig build run-defunctionalization-boundary
zig build run-host-intrinsic-allowlist
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
zig build test --summary none -- --test-filter "boundary elaboration"
zig build test --summary none -- --test-filter "elaboration certificate"
zig build test --summary none -- --test-filter "boundary normal form"
zig build test --summary none -- --test-filter "provider linking"
zig build test --summary none -- --test-filter "world port lowering"
zig build test --summary none -- --test-filter "source map"
zig build test --summary none -- --test-filter "runtime agreement"
zig build test --summary none -- --test-filter "boundary closure"
zig build test --summary none -- --test-filter "effect shape"
zig build test --summary none -- --test-filter "static treaty"
zig build test --summary none -- --test-filter "world port"
zig build test --summary none -- --test-filter "program provider"
zig build test --summary none -- --test-filter "provider program"
zig build test --summary none -- --test-filter "provider harness"
zig build test --summary none -- --test-filter "evidence"
zig build test --summary none -- --test-filter "treaty"
zig build test --summary none -- --test-filter "morphism"
zig build test --summary none -- --test-filter "exchange"
zig build test --summary none -- --test-filter "journal"
zig build lint -- --max-warnings 0
```
