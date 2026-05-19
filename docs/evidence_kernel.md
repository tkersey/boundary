# Evidence Kernel

Ability's core product is typed, explicit, inspectable, replayable, durable,
transformable, and verifiable effectful computation. The proof data around that
computation is therefore part of the library spine, not incidental metadata.

`Program.Evidence` is the shared substrate for that proof data. It gives
fingerprints, versioned byte formats, validation blockers, validation reports,
certificates, authorizations, journal projections, and dependency references one
common vocabulary while preserving the existing subsystem APIs.

The public root remains `ability.effect`, `ability.ir`, `ability.program`, and
`ability.Runtime`. Evidence is exposed through a concrete `Program` type as
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
| `ability.program.plan` | program_plan | - | 1 | no | yes | yes | yes | no | no | program plan |
| `ability.session.trace` | session | - | 2 | no | yes | yes | yes | yes | yes | trace |
| `ability.session.request` | session | - | 2 | no | yes | yes | yes | yes | yes | request |
| `ability.session.response` | session | - | 2 | no | yes | yes | yes | yes | yes | response |
| `ability.session.continuation` | session | - | 2 | no | yes | yes | yes | no | yes | continuation |
| `ability.session.capsule` | capsule | - | 2 | no | yes | yes | yes | yes | yes | capsule |
| `ability.session.capsule.image` | capsule | 1 | 1 | yes | yes | yes | yes | yes | yes | capsule image |
| `ability.session.journal` | journal | 5 | 1 | yes | yes | yes | yes | no | no | journal |
| `ability.session.journal.v4` | journal | 4 | 1 | yes | yes | yes | yes | no | no | legacy journal |
| `ability.session.journal.entry` | journal | 5 | 1 | yes | yes | yes | yes | yes | no | journal entry |
| `ability.exchange.manifest` | exchange | 1 | 1 | yes | yes | yes | yes | yes | yes | exchange |
| `ability.exchange.request` | exchange | 3 | 3 | yes | yes | yes | yes | yes | yes | exchange |
| `ability.exchange.response` | exchange | 1 | 1 | yes | yes | yes | yes | yes | yes | exchange |
| `ability.exchange.provider` | exchange | 1 | 1 | yes | yes | yes | yes | yes | yes | provider manifest |
| `ability.exchange.provider.offer` | provider_harness | 1 | 1 | yes | yes | yes | yes | yes | yes | offer |
| `ability.exchange.provider.derived_manifest` | provider_harness | 1 | 1 | yes | yes | yes | yes | yes | yes | derived manifest |
| `ability.exchange.provider.derived_offer` | provider_harness | 1 | 1 | yes | yes | yes | yes | yes | yes | derived offer |
| `ability.exchange.provider.harness` | provider_harness | - | 1 | no | yes | yes | yes | yes | yes | provider harness |
| `ability.exchange.provider.request_validation` | provider_harness | - | 1 | no | yes | yes | yes | yes | yes | provider request |
| `ability.exchange.provider.response_authorization` | provider_harness | - | 1 | no | yes | yes | yes | yes | yes | provider outcome |
| `ability.exchange.provider.journal_event` | provider_harness | 5 | 1 | yes | yes | yes | yes | yes | no | provider journal |
| `ability.exchange.morphism.offer` | morphism | - | 1 | no | yes | yes | yes | yes | yes | morphism |
| `ability.exchange.capability` | capability | 1 | 1 | yes | yes | yes | yes | yes | yes | capability |
| `ability.exchange.capability.attenuation_path` | capability | - | 1 | no | yes | yes | yes | yes | yes | capability |
| `ability.exchange.route` | capability | - | 1 | no | yes | yes | yes | yes | yes | route |
| `ability.exchange.authorization` | capability | - | 1 | no | yes | yes | yes | yes | yes | authorization |
| `ability.exchange.authorization_result` | linear_session | - | 1 | no | yes | yes | yes | yes | yes | authorization |
| `ability.exchange.effect_session` | linear_session | 1 | 1 | yes | yes | yes | yes | no | yes | linear |
| `ability.exchange.capability_instance` | linear_session | 1 | 1 | yes | yes | yes | yes | yes | yes | linear |
| `ability.exchange.obligation` | linear_session | 1 | 1 | yes | yes | yes | yes | yes | yes | obligation |
| `ability.exchange.obligation.transition` | linear_session | - | 1 | no | yes | yes | yes | yes | yes | obligation |
| `ability.exchange.treaty` | treaty | 1 | 2 | no | yes | yes | yes | yes | yes | treaty |
| `ability.exchange.treaty.certificate` | treaty | 1 | 2 | no | yes | yes | yes | yes | yes | certificate |
| `ability.exchange.treaty.authorization` | treaty | - | 3 | no | yes | yes | yes | yes | yes | authorization |
| `ability.exchange.treaty.resolver` | treaty | - | 1 | no | yes | yes | yes | yes | yes | resolver |
| `ability.program.reinterpretation` | morphism | - | 2 | no | yes | yes | yes | yes | yes | reinterpretation |
| `ability.program.residualization` | residualization | - | 1 | no | yes | yes | yes | no | yes | residual |
| `ability.program.residualization.report` | residualization | - | 1 | no | yes | yes | yes | no | yes | residual |
| `ability.program.pipeline` | pipeline | - | 1 | no | yes | yes | yes | no | yes | pipeline |
| `ability.program.pipeline.certificate` | pipeline | - | 1 | no | yes | yes | yes | no | yes | pipeline |
| `ability.program.pipeline.source_map` | pipeline | - | 1 | no | yes | yes | yes | no | yes | source map |

The current journal format is v5 because provider-side journal metadata now has
its own event fields. The v4 domain remains registered because legacy v4 decode
is still part of the compatibility contract.

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

## Treaty Example

A Treaty certificate view cites request, provider, offer, capability, route, and
treaty refs. A Treaty authorization view cites request, response, provider,
capability, route, treaty, and obligation refs when present.

Treaty resolver failures lower to `Evidence.Blocker` with `source = .treaty`.
Successful treaty validation produces an `Evidence.Report` with no error
blockers.
