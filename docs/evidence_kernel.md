# Evidence Kernel

Boundary's core product is typed, explicit, inspectable, replayable, durable,
transformable, and verifiable effectful computation. The proof data around that
computation is therefore part of the library spine, not incidental metadata.

`Program.Evidence` is the shared substrate for that proof data. It gives
fingerprints, versioned byte formats, validation blockers, validation reports,
certificates, authorizations, journal projections, and dependency references one
common vocabulary while preserving the existing subsystem APIs.

The public root remains `boundary.effect`, `boundary.ir`, `boundary.program`, and
`boundary.Runtime`. Evidence is exposed through a concrete `Program` type as
`Program.Evidence`.

## Evidence Domains

Fingerprints are deterministic semantic witnesses. They are not request tokens,
cryptographic signatures, authentication grants, or transport security. Hosts
still own identity, signing, encryption, storage, transport, scheduling,
networking, provider execution, provider lifecycle, and cancellation side
effects.

Request tokens remain local in-process misuse guards. They are not serialized
and are excluded from Evidence refs, dependencies, reports, certificates,
authorizations, and journal projections.

Format versions govern encoded bytes. Fingerprint versions govern canonical
digest semantics. Journal versions govern journal event encoding.
Certificates and authorizations are snapshots of validated dependency graphs.

Current domains are registered in `Program.Evidence.domains`:

| Domain | Owner | Format | Fingerprint | Bytes | Stable audit | Tokens excluded | Runtime ids excluded | Journal refs | Certificate refs | Existing coverage |
| --- | --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- |
| `boundary.program.plan` | program_plan | - | 1 | no | yes | yes | yes | no | no | program plan |
| `boundary.session.trace` | session | - | 2 | no | yes | yes | yes | yes | yes | trace |
| `boundary.session.request` | session | - | 2 | no | yes | yes | yes | yes | yes | request |
| `boundary.session.response` | session | - | 2 | no | yes | yes | yes | yes | yes | response |
| `boundary.session.continuation` | session | - | 2 | no | yes | yes | yes | no | yes | continuation |
| `boundary.session.capsule` | capsule | - | 2 | no | yes | yes | yes | yes | yes | capsule |
| `boundary.program.capsule.image` | capsule | 1 | 1 | yes | yes | yes | yes | yes | yes | capsule image |
| `boundary.program.session.journal` | journal | 6 | 1 | yes | yes | yes | yes | no | no | journal |
| `boundary.program.session.journal.v4` | journal | 4 | 1 | yes | yes | yes | yes | no | no | legacy journal |
| `boundary.session.journal.entry` | journal | 6 | 1 | yes | yes | yes | yes | yes | no | journal entry |
| `boundary.exchange.manifest` | exchange | 1 | 1 | yes | yes | yes | yes | yes | yes | exchange |
| `boundary.exchange.request` | exchange | 3 | 3 | yes | yes | yes | yes | yes | yes | exchange |
| `boundary.exchange.response` | exchange | 1 | 1 | yes | yes | yes | yes | yes | yes | exchange |
| `boundary.exchange.provider.identity` | exchange | - | 1 | no | yes | yes | yes | yes | yes | provider identity |
| `boundary.exchange.provider` | exchange | 2 | 2 | yes | yes | yes | yes | yes | yes | provider manifest |
| `boundary.exchange.provider_offer` | provider_harness | 1 | 1 | yes | yes | yes | yes | yes | yes | offer |
| `boundary.exchange.provider.derived_manifest` | provider_harness | 1 | 1 | yes | yes | yes | yes | yes | yes | derived manifest |
| `boundary.exchange.provider.derived_offer` | provider_harness | 1 | 1 | yes | yes | yes | yes | yes | yes | derived offer |
| `boundary.exchange.provider.harness` | provider_harness | - | 1 | no | yes | yes | yes | yes | yes | provider harness |
| `boundary.exchange.provider.request_validation` | provider_harness | - | 1 | no | yes | yes | yes | yes | yes | provider request |
| `boundary.exchange.provider.response_authorization` | provider_harness | - | 1 | no | yes | yes | yes | yes | yes | provider outcome |
| `boundary.exchange.provider.journal_event` | provider_harness | 6 | 1 | yes | yes | yes | yes | yes | no | provider journal |
| `boundary.exchange.provider_program.execution` | provider_harness | - | 1 | no | yes | yes | yes | yes | yes | provider program |
| `boundary.exchange.provider_program.mapping` | provider_harness | - | 1 | no | yes | yes | yes | yes | yes | program provider |
| `boundary.exchange.provider_program.nested_request` | provider_harness | - | 1 | no | yes | yes | yes | yes | yes | nested provider |
| `boundary.exchange.morphism_offer` | morphism | - | 1 | no | yes | yes | yes | yes | yes | morphism |
| `boundary.exchange.capability` | capability | 1 | 1 | yes | yes | yes | yes | yes | yes | capability |
| `boundary.exchange.capability.path` | capability | - | 1 | no | yes | yes | yes | yes | yes | capability |
| `boundary.exchange.route` | capability | - | 1 | no | yes | yes | yes | yes | yes | route |
| `boundary.exchange.authorization` | capability | 1 | 1 | yes | yes | yes | yes | yes | yes | authorization |
| `boundary.exchange.authorization.result` | linear_session | - | 1 | no | yes | yes | yes | yes | yes | authorization |
| `boundary.exchange.effect_session` | linear_session | 1 | 1 | yes | yes | yes | yes | no | yes | linear |
| `boundary.exchange.capability_instance` | linear_session | 1 | 1 | yes | yes | yes | yes | yes | yes | linear |
| `boundary.exchange.obligation` | linear_session | 1 | 1 | yes | yes | yes | yes | yes | yes | obligation |
| `boundary.exchange.obligation.transition` | linear_session | - | 1 | no | yes | yes | yes | yes | yes | obligation |
| `boundary.exchange.treaty` | treaty | 1 | 4 | no | yes | yes | yes | yes | yes | treaty |
| `boundary.exchange.treaty.certificate` | treaty | 1 | 4 | no | yes | yes | yes | yes | yes | certificate |
| `boundary.exchange.treaty.authorization` | treaty | 4 | 4 | yes | yes | yes | yes | yes | yes | authorization |
| `boundary.exchange.treaty.authorization.v3` | treaty | 3 | 3 | yes | yes | yes | yes | yes | yes | legacy authorization |
| `boundary.exchange.treaty.authorization.v2` | treaty | 2 | 2 | yes | yes | yes | yes | yes | yes | legacy authorization |
| `boundary.exchange.treaty.resolver` | treaty | - | 1 | no | yes | yes | yes | yes | yes | resolver |
| `boundary.session.reinterpret` | morphism | - | 2 | no | yes | yes | yes | yes | yes | reinterpretation |
| `boundary.program.residualization` | residualization | - | 1 | no | yes | yes | yes | no | yes | residual |
| `boundary.program.residualization.report` | residualization | - | 1 | no | yes | yes | yes | no | yes | residual |
| `boundary.program.pipeline` | pipeline | - | 1 | no | yes | yes | yes | no | yes | pipeline |
| `boundary.program.pipeline.certificate` | pipeline | - | 1 | no | yes | yes | yes | no | yes | pipeline |
| `boundary.program.pipeline.source_map` | pipeline | - | 1 | no | yes | yes | yes | no | yes | source map |
| `boundary.evidence.semantic_body` | semantic_boundary | - | 1 | no | yes | yes | yes | yes | yes | semantic body |
| `boundary.evidence.host_intrinsic` | semantic_boundary | 1 | 1 | no | yes | yes | yes | yes | yes | host intrinsic |
| `boundary.evidence.defunctionalization_report` | semantic_boundary | - | 1 | no | yes | yes | yes | yes | yes | defunctionalization |
| `boundary.evidence.defunctionalization_policy` | semantic_boundary | - | 1 | no | yes | yes | yes | yes | yes | intrinsic allowlist |
| `boundary.evidence.closure.effect_shape` | boundary_closure | - | 1 | no | yes | yes | yes | yes | yes | effect shape |
| `boundary.evidence.closure.static_treaty_plan` | boundary_closure | - | 2 | no | yes | yes | yes | yes | yes | static treaty |
| `boundary.evidence.closure.policy` | boundary_closure | - | 1 | no | yes | yes | yes | yes | yes | boundary closure policy |
| `boundary.evidence.closure.graph` | boundary_closure | - | 1 | no | yes | yes | yes | yes | yes | closure graph |
| `boundary.evidence.closure.report` | boundary_closure | - | 1 | no | yes | yes | yes | yes | yes | boundary closure |
| `boundary.evidence.closure.certificate` | boundary_closure | 1 | 1 | no | yes | yes | yes | yes | yes | closure certificate |
| `boundary.evidence.closure.world_port` | boundary_closure | 1 | 2 | no | yes | yes | yes | yes | yes | world port |
| `boundary.evidence.elaboration.certificate` | boundary_elaboration | 1 | 1 | no | yes | yes | yes | yes | yes | elaboration certificate |
| `boundary.evidence.elaboration.source_map` | boundary_elaboration | - | 1 | no | yes | yes | yes | yes | yes | elaboration map |
| `boundary.evidence.elaboration.effect_row` | boundary_elaboration | - | 1 | no | yes | yes | yes | yes | yes | elaboration effects |
| `boundary.evidence.elaboration.trace_map` | boundary_elaboration | - | 1 | no | yes | yes | yes | yes | yes | elaboration trace |
| `boundary.evidence.elaboration.normal_form` | boundary_elaboration | - | 1 | no | yes | yes | yes | yes | yes | normal form |
| `boundary.evidence.target.world_surface` | boundary_target | 1 | 1 | no | yes | yes | yes | yes | yes | world surface |
| `boundary.evidence.target.world_port_table` | boundary_target | - | 1 | no | yes | yes | yes | yes | yes | world port table |
| `boundary.evidence.target.world_value_table` | boundary_target | - | 1 | no | yes | yes | yes | yes | yes | world value table |
| `boundary.evidence.target.world_dispatch_table` | boundary_target | - | 1 | no | yes | yes | yes | yes | yes | world dispatch |
| `boundary.evidence.target.world_surface_profile` | boundary_target | - | 1 | no | yes | yes | yes | yes | yes | surface profile |
| `boundary.evidence.target.world_replay_key_recipe` | boundary_target | - | 1 | no | yes | yes | yes | no | yes | replay key |
| `boundary.evidence.target.policy` | boundary_target | - | 2 | no | yes | yes | yes | yes | yes | boundary target policy |
| `boundary.evidence.target.certificate` | boundary_target | 2 | 2 | no | yes | yes | yes | yes | yes | certified boundary target |
| `boundary.evidence.target.evidence_map` | boundary_target | - | 1 | no | yes | yes | yes | yes | yes | evidence |
| `boundary.evidence.target.normalization.policy` | boundary_target | - | 1 | no | yes | yes | yes | no | yes | normalization policy |
| `boundary.evidence.target.normalization.redex` | boundary_target | - | 1 | no | yes | yes | yes | no | yes | redex |
| `boundary.evidence.target.normalization.rule` | boundary_target | - | 1 | no | yes | yes | yes | no | yes | rewrite rule |
| `boundary.evidence.target.normalization.step` | boundary_target | - | 1 | no | yes | yes | yes | no | yes | rewrite step |
| `boundary.evidence.target.normalization.trace` | boundary_target | - | 1 | no | yes | yes | yes | no | yes | normalization trace |
| `boundary.evidence.target.normalization.certificate` | boundary_target | 1 | 1 | no | yes | yes | yes | no | yes | normalization |
| `boundary.evidence.target.normalization.route_lowering` | boundary_target | - | 1 | no | yes | yes | yes | no | yes | route lowering |
| `boundary.evidence.target.normalization.plan_builder` | boundary_target | - | 1 | no | yes | yes | yes | no | yes | plan builder |
| `boundary.evidence.target.module` | boundary_target | 1 | 1 | yes | yes | yes | yes | no | yes | certified boundary module |
| `boundary.evidence.target.module.manifest` | boundary_target | 1 | 1 | yes | yes | yes | yes | no | yes | module manifest |
| `boundary.evidence.target.module.import_surface` | boundary_target | 1 | 1 | yes | yes | yes | yes | no | yes | import surface |
| `boundary.evidence.target.module.export_surface` | boundary_target | 1 | 1 | yes | yes | yes | yes | no | yes | export surface |
| `boundary.evidence.target.module.graph` | boundary_target | 1 | 1 | yes | yes | yes | yes | no | yes | module graph |
| `boundary.evidence.target.module.program_plan_image` | boundary_target | 1 | 1 | yes | yes | yes | yes | no | yes | program plan image |
| `boundary.evidence.target.module.value_schema_image` | boundary_target | 1 | 1 | yes | yes | yes | yes | no | yes | value schema image |
| `boundary.evidence.target.module.loaded` | boundary_target | - | 1 | no | yes | yes | yes | no | yes | loaded module |
| `boundary.evidence.target.module.loaded_session` | boundary_target | - | 1 | no | yes | yes | yes | no | yes | loaded session |

The current journal format is v6 because provider-program execution adds
provider-side started, parked, nested request/response, resumed, completed,
rejected, and failed events. The v4 domain remains registered because legacy v4
decode is still part of the compatibility contract.

The module domains cover deterministic Certified Boundary Module bytes,
manifest/import/export surfaces, the section dependency graph, ProgramPlan and
value-schema image summaries, and loaded inspection/session witnesses. They are
semantic witnesses, not cryptographic signatures.

## Evidence Refs

`Evidence.Ref` is a compact reference to an evidence object:

- domain id
- fingerprint
- optional format version
- optional label
- optional branch id
- optional site index
- optional kind tag

Refs do not replace typed objects. They give blockers, reports, certificates,
authorizations, and journal projections one shared reference language. Helpers
such as `refForRequestEnvelope`, `refForResponseEnvelope`,
`refForProviderManifest`, `refForProviderOffer`, `refForProviderHarness`,
`refForCapability`, `refForRoute`, `refForTreaty`, and
`refForTreatyAuthorization` adapt existing subsystem objects without changing
their native APIs.

## Dependencies

`Evidence.Dependency` pairs a role with a ref. `Evidence.DependencyGraph`
provides deterministic ordering, duplicate checks, role lookup, required-role
checks, and a stable graph fingerprint.

Use dependency roles to make proof snapshots inspectable:

- `request`, `response`, `provider`, `provider_harness`, `offer`
- `capability`, `attenuated_capability`, `route`, `authorization`
- `effect_session`, `capability_instance`, `obligation`
- `treaty`, `treaty_certificate`, `treaty_authorization`
- `pipeline`, `residual_program`, `journal_entry`, `capsule_image`
- `elaboration_certificate`, `elaboration_source_map`,
  `elaboration_effect_row`, `elaboration_trace_map`, `normal_form`

## Fingerprint Builder

`Evidence.FingerprintBuilder` wraps deterministic hashing with an explicit
domain and fingerprint version. It supports stable field labels, fixed-endian
integers, length-prefixed bytes, nested refs, value fingerprints, and optional
fields. It deliberately has no pointer, allocator, runtime, thread, or request
token API.

Existing fingerprints are not migrated automatically. Adapters can use the
builder for new evidence projections while legacy fingerprint functions remain
authoritative until a versioned migration is intentionally made.

## Blockers

`Evidence.Blocker` is the shared blocker shape:

- domain, tag, severity, short code, summary
- optional subject and primary refs
- related refs
- optional branch, site, response kind, and usage mode
- source subsystem

Subsystem-specific blockers remain available. They should lower to
`Evidence.Blocker` where reports, certificates, or journals need a common view.

## Reports

`Evidence.Report` is a validation result. Reports carry a subject ref, report
domain, dependencies, blockers, warnings, success flag, report fingerprint,
optional policy fingerprint, and optional summary.

Reports are not durable certificates by default. They are validation outputs.
Use `Report.ok`, `Report.withBlockers`, `hasErrors`, `assertOk`,
`blockerCount`, and `dependencyFingerprint` for common report handling.

## Certificates And Authorizations

`Evidence.CertificateView` and `Evidence.AuthorizationView` are shared snapshot
views over existing typed certificates and authorization sidecars. The original
types still own their exact public API and fingerprint. The Evidence views make
dependency graphs explicit and comparable.

Initial adapters include Treaty certificate and Treaty authorization helpers,
and the same pattern applies to ProviderHarness response authorization,
Pipeline certificates, and residualization reports.

## Journal Projections

`Evidence.JournalProjection` describes how an evidence object can be projected
into one or more journal events. It records the evidence ref, suggested event
kind, dependency refs, summary metadata, optional branch id, and an optional
payload-builder hook.

Journal projections prevent drift between validation/certificate metadata and
journal metadata. They do not require every event to be generated
automatically.

## Policy Summaries

`Evidence.PolicySummary` gives policies one common citation shape without
replacing rich policy types. It can cite policy domains, policy fingerprints,
labels, enum flags, byte limits, usage modes, response-use classes, branch
policies, replay policies, and summary refs.

## Defunctionalization Boundary

`Evidence.SemanticBody` classifies every semantic execution body as
`boundary_program`, `declarative`, `residualized_program`, `pipeline`,
`kernel_primitive`, `host_intrinsic`, or `unknown`.

`Evidence.HostIntrinsic` describes opaque host behavior with an explicit label,
kind, owner subsystem, associated refs, policy summaries, tags, metadata, and
dependencies. Its fingerprint excludes function pointer addresses, allocator
pointers, runtime addresses, thread IDs, request tokens, and nondeterministic
host identity.

`Evidence.DefunctionalizationReport` counts body classifications for a scope and
lowers to `Evidence.Report`. `Evidence.DefunctionalizationPolicy` can reject
host intrinsics, reject unknown bodies, allowlist intrinsics, reject dynamic
mappers, require program-backed providers, require declarative/static morphisms,
and express route preferences for less opaque treaty selection.

## Boundary Closure

`Program.BoundaryClosure.EffectShape` records the static surface a closure proof
is allowed to inspect: root/program refs, operation and after site fingerprints,
requirement/op identity, value-ref shapes, semantic labels, source evidence refs,
and explicit runtime-guard or request-value dependence flags. It is not a
request envelope and never includes request tokens or concrete payload bytes.

`Program.BoundaryClosure.StaticTreatyPlan` is a shape-level dry run over
provider offers, morphism offers, capabilities, treaty policy, and
defunctionalization policy. It records deterministic route selection when
possible, or blockers when the shape is unhandled, ambiguous, missing
capability, intrinsic-only under strict policy, or otherwise unsupported.

`Program.BoundaryClosure.Graph` records deterministic closure nodes and edges.
`Program.BoundaryClosure.Report` summarizes closed shape counts, host
intrinsics, world ports, unknowns, route body classes, blockers, and policy.
`Program.BoundaryClosure.Certificate` binds graph/report consistency and exposes
an `Evidence.CertificateView` for World-facing handoff.

`Program.BoundaryClosure.WorldPort` describes a declared host/world boundary
using stable metadata only. Its fingerprint excludes runtime addresses, request
tokens, provider handles, allocator identity, threads, sockets, and concrete
world implementation state.

`Program.BoundaryClosure.Policy` fingerprints the proof policy: closed-shape
requirements, runtime-guard acceptance, host-intrinsic/world-port allowlists,
unknown-body rejection, ambiguity rejection, route preferences, and nested-depth
bounds. Boundary closure blockers lower to `Evidence.Blocker` with the
`boundary_closure` source subsystem.

The BoundaryClosure Evidence layer does not execute providers, serialize world
implementations, widen the public root, or claim cryptographic attestation. It
is the contract an adjacent `world` interpreter can consume.

## Version Bump Policy

- Bump a format version only when encoded bytes change.
- Bump a fingerprint version only when canonical digest semantics change.
- Bump a journal version only when journal event encoding changes.
- Do not bump versions for additive adapters that expose the same existing
  fingerprints and bytes through Evidence refs or reports.
- Never include request tokens, allocator addresses, runtime addresses, thread
  ids, raw pointers, or host context in semantic fingerprints.

## Adding Evidence

For a new evidence object:

1. Register a domain and version.
2. Define the canonical digest input or cite an existing fingerprint.
3. Expose an `Evidence.Ref`.
4. Expose dependencies as `Evidence.Dependency` values.
5. Validate into an `Evidence.Report`.
6. Snapshot into a certificate or authorization view when needed.
7. Project journal entries when host replay/audit needs them.
8. Add tests for domain registry parity, ref stability, dependency fingerprint,
   report fingerprint, blocker lowering, and unchanged legacy fingerprints.

## ProviderHarness Example

ProviderHarness keeps deterministic provider offers as the treaty/catalog
artifact. The Evidence view should cite:

- provider harness ref
- derived provider manifest ref
- derived provider offer refs
- request envelope ref
- treaty certificate ref
- route/capability refs
- response envelope and treaty authorization refs when a response is built

Provider-side malformed request, offer mismatch, and handler rejection blockers
lower to `Evidence.Blocker` with `source = .provider_harness`.

Program-backed provider handlers add three provider-harness domains:
`provider_program_execution`, `provider_program_mapping`, and
`provider_program_nested_request`. A provider-program execution ref cites the
parent request envelope/request fingerprints, treaty and certificate
fingerprints, provider and offer fingerprints, route and capability
fingerprints, handler Program label, handler ProgramPlan hash, branch id, and
nested turn index. Mapping refs witness the deterministic request-to-args and
result-to-outcome mapping. Nested-request refs link a handler Program's yielded
request back to the parent provider execution.

Provider-program journal projections use journal format v6 events:
`provider_program_started`, `provider_program_parked`,
`provider_program_nested_request`, `provider_program_nested_response`,
`provider_program_resumed`, `provider_program_completed`,
`provider_program_rejected`, and `provider_program_failed`. The response packet
can cite the provider-program execution fingerprint without changing response
envelope bytes. These fingerprints are deterministic semantic witnesses, not
authorization secrets or cryptographic signatures.

## Treaty Example

A Treaty certificate view cites request, provider, offer, capability, route, and
treaty refs. A Treaty authorization view cites request, response, provider,
capability, route, treaty, and obligation refs when present.

Treaty resolver failures lower to `Evidence.Blocker` with `source = .treaty`.
Successful treaty validation produces an `Evidence.Report` with no error
blockers.

Defunctionalization blockers such as `intrinsic_provider_rejected`,
`intrinsic_morphism_rejected`, `unknown_semantic_body`,
`non_defunctionalized_route`, `unallowlisted_intrinsic`, and
`intrinsic_count_exceeded` lower through the same blocker/report path.
