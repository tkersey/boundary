Iteration: 6

# Boundary Normalization Calculus Execution Plan

## Round Delta
- Converted the spec-pipeline handoff into an executable implementation campaign with dependency-ordered waves.
- Added the governing proof gate: a residual-redex audit must back every `strict_closed`, `world_ports_only`, and `assertNoSearchHotPath` claim.
- Locked runtime `Target.compile` as artifact/data compilation only, not a public VM or execution API.

## Summary
Build `Program.BoundaryClosure.Elaboration.Target.Normalization` as an additive, internal proof-carrying rewrite pass. First wave adds evidence domains, model types, and validation; the core wave builds deterministic PlanBuilder rewriting and provider/nested/world-port rules; closure wave integrates Target, docs, examples, and proof. Done means supported direct, nested, and WorldPort graphs normalize into residual `ProgramPlan` data, generated plans pass `FromResidual`, unsupported internal redexes fail closed, and the full Zig proof bundle passes.

## Non-Goals/Out of Scope
No World implementation, concrete ABI, WASM ABI, scheduler, async runtime, storage backend, xitdb integration, network/transport, provider lifecycle, service discovery, host intrinsic execution, retry logic, parser/source language, public VM API, Artifact API, cryptographic/security layer, public-root widening, `ProgramValue` widening, serializable request tokens, cross-thread sessions, arbitrary host/context serialization, or allocator/thread serialization.

## Scope Change Log
scope_change=none; reason=plan preserves the spec-pipeline scope and user milestone boundaries; approved_by=user_brief

## Interfaces/Types/APIs Impacted
- Add `Program.BoundaryClosure.Elaboration.Target.Normalization` under existing Target namespace only.
- Add `Normalization.Input`, `Policy`, `Redex`, `RewriteRule`, `RewriteStep`, `Trace`, `Certificate`, blocker tags, and deterministic fingerprint helpers.
- Add version aliases: `boundary_normalization_redex_fingerprint_version`, `boundary_normalization_rule_fingerprint_version`, `boundary_normalization_step_fingerprint_version`, `boundary_normalization_trace_fingerprint_version`, `boundary_normalization_certificate_format_version`, `boundary_normalization_certificate_fingerprint_version`, `boundary_route_lowering_fingerprint_version`, optional `boundary_plan_builder_fingerprint_version`.
- Extend Target with `compileComptime` normalization path, runtime `compile` artifact path, `NormalizationTrace`, `NormalizationCertificate`, and optional exposed `Redexes`/`RewriteSteps`.
- Enhance internal `PlanBuilder`; do not expose it as public IR or VM API.

## Data Flow
1. Validate `Normalization.Input`: checked closure certificate, root/provider/provider-program/static-plan/WorldPort refs, provider harness refs, policy compatibility, depth/step caps.
2. Copy root `ProgramPlan` into PlanBuilder; discover operation/after/protocol/world-port redexes.
3. Sort redexes deterministically; select rule from certified `StaticTreatyPlan`, provider metadata, morphism/pipeline metadata, or `WorldPort`.
4. Apply provider/nested/world-port/already-normal/unsupported rules; emit `RewriteStep` and blockers; discover nested provider redexes.
5. Repeat to fixed point or fail-closed blocker/depth/cycle/step cap.
6. Finalize residual `ProgramPlan`; run residual-redex audit; compute `NormalForm`.
7. Validate generated residual plan via `FromResidual`.
8. Generate SourceMap, TraceMap, EvidenceMap, EffectRow, NormalizationTrace, NormalizationCertificate, WorldSurface tables, and Target.Certificate.

## Edge Cases/Failure Modes
- Provider program missing, function-backed, schema mismatch, arg/result mismatch, unsupported mapping, unsupported op mode.
- Nested provider cycle, missing nested static plan, depth exceeded, unsupported nested mapping.
- WorldPort missing, shape mismatch, policy rejected, or lowering failure.
- Residual internal redex remains after fixed point.
- Generated plan hash/map mismatch fails `FromResidual`.
- `strict_closed` with any residual WorldPort or `world_ports_only` with unsupported internal blocker.
- Runtime/comptime fingerprint divergence for equivalent static inputs.

## Tests/Acceptance
- Unit tests for redex/rule/step/trace/certificate fingerprints, deterministic ordering, tamper rejection, and evidence refs.
- PlanBuilder tests for root copy, provider function copy, deterministic symbol renaming, remapping, schema refs, source metadata, and residual plan hash.
- Provider linking tests for transform, scalar/product/sum payloads, unit args, result-to-resume, and rejection paths.
- Nested linking tests for recursive success, missing plan, cycle, depth cap, unsupported mapping.
- WorldPort tests for certified lowering, dense table/dispatch entries, source path, no host execution, policy rejection.
- Target tests for generated `FromResidual`, supplied residual compatibility, compileComptime/runtime parity, no-search hot path, and normal-form claims.
- Examples/build steps: `run-boundary-normalization-provider`, `run-boundary-normalization-nested`, `run-boundary-normalization-ports`.
- Final proof commands: `zig version`; `zig fmt --check build.zig src examples test bench`; `git diff --check`; `zig build --summary all`; all new run steps; `zig build test --summary all`; focused filters for normalization/redex/rewrite/trace/provider/world-port/maps/normal-form/from-residual/runtime-agreement/boundary-closure/elaboration/evidence/treaty/morphism/exchange/journal; `zig build lint -- --max-warnings 0`.

## Requirement-to-Test Traceability
| Requirement | Acceptance check |
| --- | --- |
| Normalization models/domains | version registry and stable fingerprint tests |
| Input/policy validation | checked ref/policy mismatch tests and compile-fail fixtures |
| Deterministic worklist | redex ordering, provider copy order, step order, parity tests |
| Provider rewrite | direct provider example plus provider-linking tests |
| Nested rewrite | nested example plus cycle/depth/missing-plan tests |
| WorldPort rewrite | ports example plus dispatch/table/source/trace tests |
| NormalForm integrity | residual-redex audit, strict/world-port/blocker tests |
| Target integration | generated `FromResidual`, target certificate, compileComptime/runtime parity |
| Non-goals | root export check, no `ProgramValue` widening, no host execution assertions |

## Rollout/Monitoring
- Work on a feature branch from latest `main`; re-check `git status --short`, branch, and SHA before editing.
- Keep changes additive and reviewable: evidence/model layer first, then PlanBuilder, then rules, then Target integration, then examples/docs/tests.
- Monitor proof by running focused tests after each wave and the full bundle before handoff.
- Track generated artifact fingerprints in example output for review, but treat tests/certificates as proof, not stdout alone.

## Rollback/Abort Criteria
Abort if generated residual plans fail `FromResidual`, unsupported internal redexes remain silently, Target certificates stop binding maps/tables/trace/certs, normal-form claims contradict residual effects, public root or `ProgramValue` widens, host intrinsics execute, runtime/comptime parity diverges without blocker, or existing PR #115/#116 behavior regresses. Roll back by reverting the additive normalization namespace, examples, docs, tests, and build-step entries together.

## Assumptions/Defaults
- assumption=prior_state; provenance=spec pass verified `main` SHA `672759cd1c5c18783d42a2c7124182ecbfa3beed` on 2026-05-26; confidence=medium; verification_plan=re-run branch/SHA/status before implementation.
- assumption=runtime_compile_shape; provenance=current repo has `compileComptime` only; confidence=medium; verification_plan=implement runtime compile as data/artifact API and reject public execution semantics in review.
- assumption=stretch_rules; provenance=user marked stretch only if safe; confidence=high; verification_plan=emit blockers unless full rule evidence and tests are complete.
- assumption=proof_bar; provenance=user supplied exact proof bundle; confidence=high; verification_plan=run bundle before final implementation handoff.

## Decision Log
- D1: Normalization lives under `Elaboration.Target.Normalization`; rationale=no public root widening.
- D2: `FromResidual` remains mandatory validation for generated and supplied residual plans; rationale=keeps PR #115 authority boundary.
- D3: Unsupported redexes fail closed as blockers; rationale=prevents tolerant internal-state acceptance.
- D4: Residual-redex audit is required before normal-form and no-search claims; rationale=prevents convincing evidence over invalid residual code.
- D5: WorldSurface remains semantic and target-neutral; rationale=World chooses ABI.
- D6: Runtime `Target.compile` produces artifacts/data, not a public VM or execution path; rationale=preserves non-goals.

## Decision Impact Map
| decision_id | impacted_sections | follow_up_action |
| --- | --- | --- |
| D1 | Interfaces, Implementation Brief | add namespace without root export |
| D2 | Data Flow, Tests, Rollback | validate generated residual plan through `FromResidual` |
| D3 | Edge Cases, Tests | add unsupported blocker and compile-fail coverage |
| D4 | Tests, Adversarial Findings | implement residual-redex scan and strengthen `assertNoSearchHotPath` |
| D5 | Interfaces, Data Flow | keep WorldSurface ABI-free and dense dispatch only |
| D6 | Interfaces, Assumptions | document and test runtime compile as artifact/data surface |

## Open Questions
None.

## Stakeholder Signoff Matrix
| stakeholder | owner | status | required signal |
| --- | --- | --- | --- |
| product | Boundary maintainer | ready | milestone behavior and non-goals preserved |
| engineering | implementer/reviewer | ready | full proof bundle green |
| operations | World-adjacent consumer | ready | target-neutral WorldSurface and no-search dispatch proven |
| security | reviewer | ready | no security claims, signing, encryption, token serialization, or host execution added |

## Adversarial Findings
- lens=feasibility; type=risk; severity=medium; section=PlanBuilder; decision=D1; probability=medium; impact=high; trigger=PlanBuilder cannot rewrite yield/call shapes deterministically; status=mitigated by implementing PlanBuilder primitives before rules.
- lens=operability; type=risk; severity=medium; section=Interfaces; decision=D6; probability=medium; impact=high; trigger=runtime compile drifts into execution API; status=mitigated by artifact/data-only contract.
- lens=risk; type=risk; severity=high; section=NormalForm; decision=D4; probability=medium; impact=critical; trigger=residual internal redex remains after normalization; status=mitigated by residual-redex audit plus no-search assertion.
- lens=verification; type=preference; severity=low; section=Examples; decision=D2; status=accepted that examples are smoke proof only, backed by tests.

## Convergence Evidence
clean_rounds=2
press_pass_clean=true
new_errors=0
last_two_no_delta_proof=iterations 5 and 6 both delta_kind=none with non-empty evidence
press_sections_checked=Interfaces/Types/APIs Impacted, Data Flow, Rollback/Abort Criteria, Requirement-to-Test Traceability
implementation_ready_reason=all major requirements have acceptance checks, risks have mitigations, and no blocking open questions remain
minor_concerns=runtime compile exact helper shape may adjust during implementation but cannot change the artifact/data boundary

## Contract Signals
contract_version=2
strictness_profile=balanced
blocking_errors=0
material_risks_open=0
clean_rounds=2
press_pass_clean=true
new_errors=0
rewrite_ratio=0.00
external_inputs_trusted=false
improvement_exhausted=true
stop_reason=none

## Implementation Brief
1. step=evidence-models; owner=implementation; success_criteria=new normalization domains, version aliases, blocker tags, and fingerprint tests compile.
2. step=input-policy; owner=implementation; success_criteria=`Normalization.Input` and `Policy` reject unchecked/mismatched refs and incompatible policies.
3. step=planbuilder; owner=implementation; success_criteria=root/provider copy, deterministic remap, yield replacement, WorldPort residualization, and plan hash tests pass.
4. step=rewrite-engine; owner=implementation; success_criteria=provider, nested provider, WorldPort, already-normal, and unsupported rules produce deterministic steps/blockers.
5. step=artifact-generation; owner=implementation; success_criteria=maps, effect row, normal form, trace, normalization certificate, and evidence map bind rewrite steps.
6. step=target-integration; owner=implementation; success_criteria=compileComptime and runtime compile route through normalization and generated plans pass `FromResidual`.
7. step=examples-docs-tests; owner=implementation; success_criteria=three new examples, build steps, docs, compile-fail fixtures, focused tests, full regression proof, and lint pass.

Iteration: 6
