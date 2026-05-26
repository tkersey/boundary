Iteration: 7

# Certified Boundary Target Implementation Plan

## Round Delta
- Converted the completed spec-pipeline handoff into an executable implementation campaign with dependency-ordered waves, abort gates, and concrete proof surfaces.
- Hardened the architecture around one authority rule: `Target.compile*` synthesizes residual data, then validates through `Elaboration.FromResidual` before deriving WorldSurface tables.
- Added one accretive proof mechanism: implement target assertions through a shared `Target.Conformance` checker used by comptime/runtime paths and examples.

## Summary
Build `Program.BoundaryClosure.Elaboration.Target` as an additive Boundary-side compiler target: synthesize an ordinary residual `ProgramPlan`, validate it through `FromResidual`, then emit a target-neutral `WorldSurface` plus dense world-port/value/dispatch tables, maps, replay metadata, and a target certificate. First wave adds evidence domains, target data models, and policy/certificate scaffolding; later waves add `PlanBuilder`, compile paths, examples, docs, and proof. Done means strict, nested-provider, and explicit-world-port targets compile, run, dispatch without hot-path search, and pass the full requested Zig proof bundle.

## Non-Goals/Out of Scope
Do not implement World, scheduling, async runtime, storage, xitdb, network/transport, provider lifecycle, service discovery, host intrinsic execution, provider retry logic, parser/source language, public VM APIs, Artifact APIs, WASM ABI/imports/linear-memory/status protocol, crypto/security claims, new effect semantics, receipts/membranes/settlement, public-root widening, `ProgramValue` widening, serializable request tokens, cross-thread sessions, arbitrary host serialization, host context serialization, allocator/thread serialization, or removal of `FromResidual`, function-backed handlers, `Program.run`, `Program.Interpreter`, or `Program.Session`.

## Scope Change Log
- scope_change=none; reason=plan preserves supplied milestone scope and optional replay-profile status; approved_by=user brief

## Interfaces/Types/APIs Impacted
- `Program.BoundaryClosure.Elaboration.Target`: add `compileComptime`, `compile`, `Policy`, `Result`, `WorldSurface`, `WorldPortTable`, `WorldValueTable`, `WorldDispatchTable`, `SurfaceProfile`, `EvidenceMap`, `Certificate`, `ReplayKeyRecipe`, and `Conformance`.
- Generated comptime type exposes `Body`, `Program` if practical, world tables/maps, `EffectRow`, `NormalForm`, `Certificate`, blockers, and assertions: `assertNormalForm`, `assertWorldSurfaceReady`, `assertNoSearchHotPath`, `assertBoundedSurface`.
- Runtime `compile(allocator, input)` returns owned/deinit-able data equivalent to the comptime target for supported dynamic inputs.
- Internal-only `Elaboration.Target.PlanBuilder` copies/remaps `ProgramPlan` rows, schemas, functions, locals, blocks, instructions, terminators, requirements, ops, site metadata, and world-port metadata.
- `Program` constants add only new target/world-surface/evidence-map/replay recipe format/fingerprint versions; existing request/session/capsule/exchange/provider/treaty/journal versions stay stable unless their bytes actually change.

## Data Flow
1. Inputs: root Program, checked `BoundaryClosureCertificate`, closure graph/report/static treaty plans, provider programs/catalog facts, morphisms/pipelines, explicit `WorldPorts`, and target policy.
2. `Target.compile*` validates closure/certificate/root/provider/static-plan/world-port alignment.
3. `PlanBuilder` copies root plan, links provider plans, rewrites supported internal yield sites into provider/helper calls, recursively links nested providers, lowers explicit WorldPorts into residual op rows, and fails closed on unsupported shape/control/schema cases.
4. Generated residual `ProgramPlan` is wrapped as ordinary `Body` metadata and validated through `Elaboration.FromResidual`.
5. World-facing tables are derived from the validated residual plan and maps: residual site index -> dense `world_port_id`; value refs -> dense codec descriptors; port id -> semantic/evidence/source/trace refs.
6. Target certificate binds closure certificate, validated residual plan hash, WorldSurface/table/profile/map fingerprints, policy, providers, static plans, world ports, replay recipe, evidence refs, and blockers.
7. Future world hot path: `session.next()` -> residual site index -> dense port id -> decode via value table -> host/world ABI of World's choice -> encode response -> `session.resume(...)`.

## Edge Cases/Failure Modes
- unchecked or mismatched closure certificate: reject with target blocker and no target certificate success.
- unsupported root/provider instruction, terminator, output, nested-with, schema, or control-flow shape: fail closed; do not generate tolerant residual code.
- provider cycle/depth overflow/repeated unsupported route: reject with nested provider blockers.
- host intrinsic internal route or unknown semantic body: reject unless represented as explicit policy-allowed `WorldPort`.
- schema mismatch or cross-type conversion: reject; exact same-type/schema-index remap only when proven deterministic.
- unbounded payload/response with `require_bounded_surface=true`: reject and report profile blocker.
- dense table tampering or surface fingerprint mismatch: target certificate/check rejects; world must not use table ids across surfaces.
- runtime/comptime drift: parity tests must compare fingerprints, normal form, tables, maps, and residual plan hash for equivalent supported inputs.

## Tests/Acceptance
- API acceptance: `compileComptime` returns generated type exposing required decls; runtime `compile` returns owned result and deinit works.
- Synthesis acceptance: root copy, provider linking, nested provider linking, supported mappings, schema merge, morphism/pipeline routes, and WorldPort lowering work for positive fixtures.
- Negative acceptance: unchecked certificate, mismatched root/provider/static plan/world port, unsupported mapping/control/schema, host intrinsic internal route, nested cycle/depth, unbounded required-bounded surface all fail closed.
- Hot-path acceptance: every residual WorldPort dispatches by residual site index to dense id; no TreatyResolver, ProviderHarness, provider catalog, morphism search, closure graph traversal, evidence traversal, or string lookup is needed.
- Runtime agreement: original closure/treaty/provider path and generated residual path produce same final result for strict/nested/ports examples.
- Regression acceptance: existing closure, elaboration, defunctionalization, provider, treaty, exchange, linear session, journal, residualization, pipeline, typed-plan, and example suites remain green.

## Requirement-to-Test Traceability
| Requirement | Acceptance check |
|---|---|
| Target API and generated Body | `compile comptime`, `certified boundary target`, new examples |
| FromResidual validation authority | `from residual`, target certificate tamper tests |
| Dense world surface tables | `world surface`, `world port table`, `world value table`, `world dispatch` |
| No-search hot path | `no search hot path`, world-like fixture loop |
| Provider/root/nested linking | `root copy`, `provider linking`, `nested provider`, runtime agreement |
| Mapping/control/schema fail-closed behavior | `world port lowering`, `schema merge`, mapping/control-flow focused filters |
| Boundedness/replay metadata | `surface profile`, `bounded surface`, `replay key` |
| Regression safety | `zig build --summary all`, `zig build test --summary all`, all listed run steps, `zig build lint -- --max-warnings 0` |

## Rollout/Monitoring
- Develop on a feature branch from latest `main`; before implementation, re-check `git status --short --branch` and avoid unrelated diffs.
- Land as one additive PR with docs/examples/tests and PR summary covering API, FromResidual distinction, normal form, WorldSurface/tables/profile/replay metadata, provider linking, WorldPort lowering, no-World/non-ABI confirmation, and versions.
- Monitoring is proof-based: local Zig proof bundle, focused filters, example output, diff review, and PR review; no production runtime rollout exists for this library change.

## Rollback/Abort Criteria
Abort or back out if implementation widens the public root, widens `ProgramValue`, changes `Program.Session`/`Program.run` semantics, serializes request tokens, introduces target-specific ABI/WASM details, executes host intrinsics, bypasses `FromResidual`, accepts unsupported internal invalid state, or leaves certified internal routes requiring TreatyResolver/ProviderHarness/catalog/morphism search on the hot path.

## Assumptions/Defaults
- assumption=local main is current enough for planning as of 2026-05-26; provenance=git status showed `main...origin/main`; confidence=medium; verification_plan=fetch/rebase or confirm remote before coding.
- assumption=optional replay-profile example can defer if core target proof is complete; provenance=user marked it optional; confidence=high; verification_plan=include required replay-key tests even if optional example defers.
- assumption=runtime compile may start narrower than comptime for dynamic inputs; provenance=spec-pipeline default; confidence=medium; verification_plan=runtime/comptime parity tests define supported overlap.
- assumption=all new target evidence domains can be additive without bumping existing domains; provenance=current evidence registry has additive closure/elaboration domains; confidence=medium; verification_plan=domain registry tests and fingerprint stability tests.

## Decision Log
- D1: `Target` lives under `Program.BoundaryClosure.Elaboration.Target`; rationale=keeps public root stable and colocates with existing closure elaboration.
- D2: `FromResidual` remains validation authority; rationale=prevents parallel certificate path and preserves PR #115 architecture.
- D3: WorldSurface is target-neutral only; rationale=World chooses ABI/runtime/storage/transport and Boundary emits semantic surface.
- D4: Dense `world_port_id` is scoped to `WorldSurface.fingerprint`; rationale=fast dispatch without pretending ids are global identities.
- D5: V1 links provider programs and supported routes, not arbitrary optimizer/inliner; rationale=delivers hot-path removal with bounded implementation risk.
- D6: Implement assertions through shared `Target.Conformance`; rationale=keeps comptime/runtime/example no-search and bounded-surface checks aligned.

## Decision Impact Map
- decision_id=D1; impacted_sections=Interfaces,Implementation Brief; follow_up_action=add nested namespace only
- decision_id=D2; impacted_sections=Data Flow,Tests,Rollback; follow_up_action=target compile must call/reuse FromResidual before certificate success
- decision_id=D3; impacted_sections=Non-Goals,Docs,WorldSurface; follow_up_action=reject WASM/ABI/status/layout descriptors
- decision_id=D4; impacted_sections=Data Flow,Tests,Edge Cases; follow_up_action=surface fingerprint validation and dense-id tests
- decision_id=D5; impacted_sections=PlanBuilder,Traceability; follow_up_action=link/copy/rewrite supported shapes, fail closed otherwise
- decision_id=D6; impacted_sections=Interfaces,Tests; follow_up_action=central conformance checker backs public assertions

## Open Questions
None.

## Stakeholder Signoff Matrix
| stakeholder | owner | status | readiness condition |
|---|---|---|---|
| product | user/maintainer | locked | supplied milestone/non-goals preserved |
| engineering | implementer | ready | plan defines API, data flow, waves, proof |
| operations | maintainer | ready | no runtime deployment; proof and rollback gates defined |
| security | maintainer | ready | no crypto/security claims; evidence fingerprints remain semantic witnesses |

## Adversarial Findings
- lens=feasibility; type=risk; severity=high; section=PlanBuilder; decision=D5; status=mitigated; probability=medium; impact=high; trigger=attempting full instruction-level inlining instead of supported linking
- lens=operability; type=risk; severity=medium; section=WorldSurface; decision=D4; status=mitigated; probability=medium; impact=medium; trigger=using dense ids without surface fingerprint validation
- lens=risk; type=risk; severity=high; section=Certificate; decision=D2; status=mitigated; probability=low; impact=high; trigger=target certificate success without FromResidual-validated residual maps
- lens=scope; type=preference; severity=low; section=Examples; decision=D3; status=accepted; probability=medium; impact=low; trigger=optional replay-profile example deferred after core proof

## Convergence Evidence
clean_rounds=2
press_pass_clean=true
new_errors=0
blocking_errors_resolved=true
material_risks_treated=true
pressed_sections=Summary,Data Flow,Requirement-to-Test Traceability,Rollback/Abort Criteria
implementation_ready_reason=API placement, validation authority, failure boundaries, proof commands, and done-state are explicit
remaining_minor_concerns=runtime compile breadth may need scoping during implementation but has parity tests and defaults

## Contract Signals
contract_version=2
strictness_profile=balanced
blocking_errors=0
material_risks_open=0
clean_rounds=2
press_pass_clean=true
new_errors=0
rewrite_ratio=0.00
external_inputs_trusted=true
improvement_exhausted=true
stop_reason=none
last_two_no_delta=true

## Implementation Brief
1. step=preflight; owner=implementation; success_criteria=confirm latest `main`, inspect diff, keep unrelated changes untouched.
2. step=wave1-evidence-and-models; owner=implementation; success_criteria=new domains/constants, `Target.Policy`, blockers, world surface/table/profile/replay/certificate structs compile and have fingerprint tests.
3. step=wave2-planbuilder; owner=implementation; success_criteria=root/provider copy, schema remap, symbol rename, route rewrite, WorldPort lowering, and fail-closed blockers pass focused tests.
4. step=wave3-compile-paths; owner=implementation; success_criteria=`compileComptime` returns generated type, `compile` returns owned result, both validate through `FromResidual`, `Target.Conformance` powers assertions.
5. step=wave4-examples-docs; owner=implementation; success_criteria=`world_surface_strict`, `world_surface_nested`, `world_surface_ports` and docs explain WorldSurface, no-search hot path, dense-id scope, and non-goals.
6. step=wave5-proof-closeout; owner=verification; success_criteria=run requested fmt/diff/build/examples/focused tests/full tests/lint bundle; review diff; prepare PR summary with version/domain and non-goal confirmations.

Iteration: 7
