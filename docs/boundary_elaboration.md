# Boundary Closure Elaboration

Boundary Closure proves the configured graph is closed. Boundary Elaboration
compiles the closed graph into an ordinary residual Boundary program.
Normalization is the target-side rewrite calculus that records which certified
routes were eliminated, linked, residualized as world ports, or blocked.

`Program.BoundaryClosure.Elaboration` is an evidence and compilation surface over
a checked `Program.BoundaryClosure` result. It takes a closure certificate,
closure graph/report, root program ref, provider-program proofs, static treaty
plans, optional world ports, and an elaboration policy. The output is a residual
`ProgramPlan` body plus source/residual/evidence maps, an effect row, Boundary
Normal Form metadata, and an elaboration certificate.

It does not implement World, scheduling, async execution, storage, transport,
provider lifecycle, service discovery, host intrinsic execution, a VM API, an
Artifact API, a parser, or a new public root. The resulting plan is run with the
ordinary `Program.Session`, `Program.run`, `Program.protocol`, and
`Program.contract` surfaces.

## Closure Certificate Vs Elaboration Certificate

A Boundary Closure Certificate says the configured static graph is closed under
the selected policy, except for explicit world ports when world-boundary policy
allows them. It binds the closure graph, report, root refs, provider refs,
selected static treaty plans, world-port refs, blockers, and policy summary.

A Boundary Elaboration Certificate says a residual program was produced from
that certified graph. It binds the closure certificate ref, closure graph ref,
root program ref, residual `ProgramPlan` hash, elaborated program label,
elaboration policy fingerprint, selected treaty plan refs, inlined provider
program refs, residual world-port refs, source/residual map fingerprints,
evidence dependency refs, blocker refs, summary counts, and an
`Evidence.CertificateView`.

## EffectShape Vs RequestEnvelope

`EffectShape` is static. It names a reachable effect site by program label, plan
hash, site index, protocol op, mode, value refs, semantic label, and evidence ref.

`RequestEnvelope` is runtime. It carries concrete request bytes, request
fingerprints, token-guarded session state, payload validation, treaty response
checks, and linear obligation guards.

Elaboration uses `EffectShape` and static treaty facts. It does not serialize
request tokens or execute host handlers.

## StaticTreatyPlan Vs Elaborated Route

`StaticTreatyPlan` records the dry-run handling route for one shape: provider
candidates, morphism candidates, capability evidence, semantic-body
classification, runtime guard requirements, and blockers.

An elaborated route is the residual program structure that replaces that internal
route where the first version supports it. Program-backed provider routes are
represented as linked residual plan facts; declarative, residualized, and
pipeline routes are accepted only when their existing proof data is present.
Unsupported route shapes lower to fail-closed blockers.

## Boundary Normal Form

Boundary Normal Form means:

- certified internal Boundary-native provider routes are represented in the
  residual `ProgramPlan` where supported
- certified declarative, residualized, and pipeline morphisms are represented
  where supported
- no unresolved internal effect shape is accepted as closed
- remaining yielded effects are explicit WorldPorts
- each residual world-port site maps back to a source `EffectShape` and
  `WorldPort`
- trace and evidence correspondence is available

`NormalFormKind` has three values:

- `strict_closed`: no residual effects remain
- `world_ports_only`: only explicit residual world-port effects remain
- `partial_with_blockers`: unsupported shapes are reported

## Provider Program Linking

The first supported path is a certified program-backed provider route whose
request mapping is `payload_to_args` or `unit_args`, and whose result mapping is
`result_to_resume` or `result_to_return_now`. Provider program refs, mapping
fingerprints, static treaty plan refs, and nested provider-shape evidence are
bound into the elaboration certificate and source map.

Unsupported mappings, schema mismatches, unknown bodies, dynamic mappers, and
missing nested proofs emit blockers such as `unsupported_request_mapping`,
`unsupported_result_mapping`, `provider_arg_schema_mismatch`,
`provider_result_schema_mismatch`, and `provider_mapping_not_elaborable`.

## Nested Provider Elaboration

Nested provider programs are represented by additional provider-program refs and
source-map entries. The nested example binds the root approval route and the
nested `policy.check` route to one residual plan and records both provider
program refs in the elaboration certificate. The current closure API still emits
per-program closure certificates, so the nested certificate is carried as an
evidence dependency rather than introducing a scheduler or provider lifecycle.

## WorldPort Lowering

Explicit `WorldPort`s lower to residual operation sites. The residual program
does not invoke a host intrinsic function. It yields a Boundary request whose
site is listed in the source map and effect row. The map records the source
`EffectShape`, residual site index, `WorldPort` ref, optional host-intrinsic ref
through the world-port declaration, and trace label.

Strict elaboration rejects world ports. `world_boundary` permits only explicit
world ports and still rejects implicit internal host intrinsics.

## Certified Boundary Target

`Elaboration.Target.compileComptime` produces a Certified Boundary Target. In V1
it requires an explicit `.residual_program` or `.root` and packages that
residual program after `FromResidual` validation. Boundary Normalization then
emits redex, rule, rewrite-step, trace, and normalization-certificate evidence
for the same validated residual body. The target-neutral
`WorldSurface` binds the elaboration certificate, residual program ref, source
map, effect row, normal form, port table, value table, dispatch table, profile,
replay-key recipe, and evidence map. The target certificate binds and checks the
`WorldSurface` ref and the normalization certificate ref.

The dispatch table is the target boundary. It gives World a dense residual-site
to world-port lookup, so a generated target does not need to search the source
map on the hot path. The target certificate checks that every table ref and
fingerprint matches the `WorldSurface`, that each world port has payload, resume,
and result value descriptors, and that policy bounds such as `max_world_ports`
and `max_value_descriptors` hold.

`Target.Module` is the wire-transfer image namespace for the certified target.
It can emit reference-only or full Certified Boundary Module bytes, validate
section graphs and fingerprints, decode a `LoadedModule` for inspection, and
check WorldPort import bindings without adding World, storage, transport, ABI,
or host execution behavior. See [boundary_module.md](boundary_module.md).

The module consumption surface reports module kind, target label, target
certificate and WorldSurface fingerprints, normal-form kind, ProgramPlan hash,
import/export projections, structured diagnostics, compatibility, dependencies,
and target-neutral import-binding reports. World still supplies ports and
chooses ABI, transport, storage, and timeline serialization.

## Source, Residual, And Evidence Maps

`Elaboration.SourceMap` records source shape refs, residual refs, source and
residual site indexes, provider program refs, static treaty plan refs, world-port
refs, dispositions, and labels.

Helpers include:

- `sourceForResidualSite`
- `residualForSourceShape`
- `worldPortForResidualSite`
- `staticPlanForElaboratedRoute`

`TraceMap`, `EffectRow`, `BoundaryNormalForm`, and the elaboration certificate
share evidence refs so a residual world-port request can be traced back to the
source effect shape, world port, closure certificate, and elaboration certificate.

## Runtime Agreement Tests

The examples run the original host-driven session path and the elaborated
residual program path for supported shapes:

- `zig build run-boundary-elaboration-strict`
- `zig build run-boundary-elaboration-nested`
- `zig build run-boundary-elaboration-world-port`

The strict and nested examples finish without residual world ports. The
world-port example yields a residual request, maps it back to the source
`EffectShape` and `WorldPort`, supplies a local fixture response, and completes.

## What This Means For World

World consumes the residual program, world-port effect row, source map, trace map,
and certificates. World still owns identity, signing, encryption, transport,
storage, scheduling, provider lifecycle, retries, cancellation, network, and host
execution. Evidence fingerprints remain deterministic semantic witnesses, not
cryptographic authorizations.

## Non-Goals

Boundary Elaboration does not add World, scheduling, async runtime behavior,
storage, networking, transport, provider lifecycle management, service discovery,
actual host intrinsic execution, retries, a parser, source language, public VM
API, Artifact API, signing, encryption, security claims, new effect semantics,
receipts, membranes, settlement, public-root widening, `ProgramValue` widening,
serializable request tokens, cross-thread sessions, arbitrary host serialization,
host context serialization, allocator serialization, or thread serialization.
