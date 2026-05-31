# Boundary WorldSurface

Boundary compiles internal algebraic-effect handling away. World interprets only
the explicit residual world surface.

## Certified Boundary Target

`Program.BoundaryClosure.Elaboration.Target` is the Boundary-side target object
for an adjacent `world` interpreter. It packages a residual `ProgramPlan` body,
Boundary Normal Form, dense world-port dispatch metadata, source/trace/evidence
maps, replay-key recipe metadata, and a target certificate.

`FromResidual` remains the validation path for a supplied or generated residual
plan. `Target.compileComptime` requires `.residual_program` or `.root`, builds
the target-neutral surface, validates the body through `FromResidual`, and binds
normalization trace/certificate evidence into the target certificate.

## WorldSurface

`WorldSurface` is metadata, not an ABI. It binds the residual program ref,
elaboration certificate, source map, effect row, normal form, `WorldPortTable`,
`WorldValueTable`, `WorldDispatchTable`, `SurfaceProfile`, and replay recipe.
The target certificate binds and checks the `WorldSurface` ref.

Boundary does not define WASM imports, native function tables, message formats,
linear memory, status codes, scheduling, storage, transport, replay persistence,
provider lifecycle, or host intrinsic execution.

## Normal Form

Boundary targets report:

- `strict_closed`: no residual effects remain.
- `world_ports_only`: only explicit residual world ports remain.
- `partial_with_blockers`: unsupported shapes remain as blockers.

Boundary Normalization produces the proof-carrying rewrite trace behind that
classification. See [boundary_normalization.md](boundary_normalization.md).

## Hot Path

The intended world hot path is:

```text
session.next()
  -> if done, return result
  -> if request, map residual site index to dense world_port_id
  -> decode payload using WorldValueTable / Boundary value metadata
  -> call world-owned host implementation using any ABI World chooses
  -> encode response using Boundary value metadata
  -> resume session
```

No hot-path `TreatyResolver`, `ProviderHarness`, provider catalog search,
morphism search, closure graph traversal, string matching, or evidence graph
traversal is required for residual world-port dispatch.

## Dense Port IDs

`world_port_id` values are dense and stable only within one
`WorldSurface.fingerprint`. World must validate the surface fingerprint before
using a dispatch table. If the fingerprint changes, the table is a new surface.

Each port also carries diagnostic keys: world-port ref, source shape ref,
residual site index/fingerprint, protocol label, op name, semantic label, and
evidence refs.

## Tables

`WorldPortTable` maps each residual world-port site to a dense id and source
shape.

`WorldValueTable` exposes payload, resume, and result value refs for each dense
port. It does not widen `ProgramValue` and does not introduce new codecs.

`WorldDispatchTable` maps residual operation site indexes to dense ids, with
explicit miss slots for site-index gaps and site fingerprints available for
validation and diagnostics.

`SurfaceProfile` summarizes port count, value descriptor count, dispatch count,
no-search readiness, and boundedness policy.

Replay metadata is the evidence-backed recipe:

```text
{ world_surface_scope_fingerprint, world_port_id, request_fingerprint, response_fingerprint }
```

Boundary emits the recipe only; journal storage and replay lookup belong to
World.

## Certified Boundary Module

`Target.Module` serializes the same target-neutral semantic surface into a
Certified Boundary Module image. Reference images identify a target already
known to the receiver. Full images carry the manifest, import/export surfaces,
ProgramPlan and value-schema summaries, WorldSurface sections, maps, evidence,
normal form, and certificate refs required for validation and inspection.

The module remains a Boundary semantic image, not a concrete World ABI. World
still chooses how to bind implementations, encode host calls, store module
bytes, and persist execution timelines. See
[boundary_module.md](boundary_module.md).

## World v0 Contract

World v0 can rely on Boundary to provide:

- residual `ProgramPlan`
- `WorldSurface` fingerprint
- dense `WorldPortTable`
- `WorldDispatchTable`
- `WorldValueTable`
- target-neutral profile metadata
- source, trace, and evidence maps
- target certificate
- normal-form kind

World v0 still owns:

- concrete ABI selection
- host intrinsic execution
- scheduling
- storage and transport
- replay storage and journal persistence
- provider lifecycle
- security, signing, and encryption if desired
