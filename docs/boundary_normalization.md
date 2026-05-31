# Boundary Normalization

Closure proves the handler graph. Normalization rewrites the graph into
Boundary Normal Form. World handles only the residual ports.

`Program.BoundaryClosure.Elaboration.Target.Normalization` is the Boundary-side
compile-time rewrite evidence layer used by Certified Boundary Targets. It is
not a public root, VM API, scheduler, async runtime, storage backend, transport,
host execution layer, or concrete ABI.

## Inputs

`Normalization.Input` binds a checked closure certificate, closure graph, root
program ref, provider harness refs, provider program declarations, static treaty
plans, morphism/pipeline refs, world ports, target policy, nested-provider depth,
and optional labels/hash overrides.

Validation is fail-closed: root refs, provider-program refs, selected static
treaty plan refs, world-port refs, closure certificate refs, and target-policy
depth limits must agree with the elaboration input before the target is built.

## Policy

`Normalization.Policy` records the target-side rewrite contract:
program-provider rewrites, nested provider rewrites, world-port residualization,
residualized morphism and pipeline hooks, host-intrinsic rejection,
unknown-body rejection, rewrite/depth caps, FromResidual validation, no-search
hot-path requirements, metadata preservation, and unsupported-redex handling.

The default posture is fail closed.

## Redexes

A redex is a static effect site in the partially normalized target body. A redex
records a fingerprint, source `EffectShape` ref, residual coordinates, origin,
selected `StaticTreatyPlan` ref, current program-plan ref/hash, semantic body,
expected lowering kind, and evidence dependencies.

Supported redex kinds are operation sites, after sites, protocol operation
shapes, world-port sites, and unsupported sites. Request tokens and runtime
pointers are not part of redex fingerprints.

## Rewrite Rules

Rewrite rules classify what may happen to a redex:

- `provider_program_call`
- `nested_provider_program_call`
- `residual_world_port`
- `residualized_morphism`
- `pipeline_adapter`
- `already_normal`
- `unsupported`

Each rule has a deterministic fingerprint, evidence dependencies, produced map
counts, and blocker refs. Unsupported redexes become blockers rather than being
silently preserved as internal residual effects.

## Rewrite Steps

`Normalization.RewriteStep` is the proof-carrying record of one rewrite. It binds
the step index, redex ref, rule ref, selected static treaty plan, source shape,
input and output plan hashes, builder-state fingerprint, provider refs,
world-port refs, morphism/pipeline refs, blockers, and a short summary.

Provider rewrites require certified program-backed providers, supported
`payload_to_args` or `unit_args` request mapping, supported `result_to_resume`
result mapping in V1, compatible schema refs, and available provider program
proofs. Nested provider rewrites use the same evidence model with depth/cycle
limits. World-port rewrites require an explicit certified `WorldPort`.

## Trace And Certificate

`Normalization.Trace` is a compile-time transformation trace, not a runtime
request trace. It binds the root program ref, closure certificate ref, ordered
rewrite steps, eliminated redex refs, residual world-port refs, unsupported
redex refs, final program-plan hash, final normal form, and evidence
dependencies.

`Normalization.Certificate` binds the normalization trace to the target policy,
final residual plan hash, SourceMap, TraceMap, EvidenceMap, EffectRow,
NormalForm, WorldSurface, blocker refs, and `Evidence.CertificateView`.

## Target Integration

`Target.compileComptime` still validates generated or supplied residual programs
through `Elaboration.FromResidual`. Normalization consumes the resulting
source-map and effect-row facts to emit deterministic redexes, rules, rewrite
steps, a normalization trace, and a normalization certificate. The generated
target exposes:

- `Target.NormalizationTrace`
- `Target.NormalizationCertificate`
- `Target.RewriteSteps`
- `Target.Redexes`

The target certificate binds the normalization certificate ref.

## World Surface

Normalization is target-neutral. Boundary emits residual `ProgramPlan` data,
Boundary Normal Form, source/trace/evidence maps, and a semantic
`WorldSurface`. World chooses the concrete ABI, host execution model, storage,
transport, scheduling, retry behavior, signing, encryption, and provider
lifecycle.

Residual effects are valid only when they are explicit certified WorldPorts.
Dense `world_port_id` values are scoped to one `WorldSurface.fingerprint`.

## Module Images

Certified Boundary Module images package the post-normalization semantic surface:
the residual ProgramPlan image, value schema image, WorldSurface sections, maps,
normal form, effect row, target certificate, normalization trace/certificate
refs, and import/export surfaces. Validation checks these fingerprints without
executing host code. Boundary still does not serialize request tokens, host
functions, host context, runtime pointers, allocators, threads, timelines,
transport, storage, or ABI choices. See [boundary_module.md](boundary_module.md).

Consumption helpers on `LoadedModule` expose the normalized surface directly:
inspection fields, import/export projections, WorldSurface lookups,
compatibility reports, validation diagnostics, dependency reports, and
target-neutral import-binding reports. These reports explain the normalized
semantic boundary; they do not run it.
