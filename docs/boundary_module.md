# Certified Boundary Module

Boundary serializes the normalized semantic boundary as a module. World
serializes execution timelines and supplies the world.

`Program.BoundaryClosure.Elaboration.Target.Module` is the module namespace for a
Certified Boundary Target. It exposes `reference`, `fullImage`, `encode`,
`decode`, `validate`, `validateSelf`, `asLoadedModule`, and
`validateReferenceAgainst` helpers on generated targets. The public package root
does not widen.

## Module Kinds

`reference_only` contains compact identity material for a receiver that already
has the same generated target: module fingerprint, target certificate
fingerprint, `WorldSurface` fingerprint, plan hash, normal-form kind, and label.

`full_module` contains the required semantic sections for validation and
inspection without the original comptime target type.

`partial_module` is reserved for explicit external dependencies. Boundary never
performs implicit storage, network, registry, or package-manager lookup.

## Image Layout

The image is sectioned and content-addressed. The header records magic bytes,
format and fingerprint versions, module kind, section count, module
fingerprint, manifest fingerprint, and total image length. The section table is
canonical by section kind and records section kind, format version, byte offset,
byte length, section fingerprint, and required/optional policy.

Encoding is deterministic: little-endian integers, length-prefixed byte arrays,
deterministic enum tags, deterministic optional fields, no native pointers, no
allocator/runtime/thread state, no function pointers, and no request tokens.
Validation rejects trailing bytes unless explicitly allowed, invalid ordering,
out-of-bounds or overlapping sections, bad fingerprints, unknown required
sections, and malformed version domains.

## Manifest

`Target.Module.Manifest` binds the module kind, target label, ProgramPlan hash,
`WorldSurface` fingerprint, target certificate fingerprint, optional
normalization certificate fingerprint, ImportSurface fingerprint, ExportSurface
fingerprint, world-port count, normal-form kind, required section refs, external
dependency refs, producer metadata, compatibility metadata, and a manifest
fingerprint.

## ImportSurface

`Target.Module.ImportSurface` lists semantic requirements the receiving World
must supply. V1 imports are residual WorldPorts. Each import carries import id,
dense `world_port_id`, `WorldPort` ref, optional host-intrinsic ref, source
effect-shape ref, residual site index/fingerprint, payload and response value
table ids, payload/response refs, mode, response kind, replay-key recipe ref,
symbolic name, required flag, and metadata hooks.

Imports are not implementations. They never serialize handlers, function
pointers, credentials, URLs, model clients, files, network endpoints, runtime
state, or request tokens. Dense `world_port_id` values remain scoped to the
`WorldSurface` fingerprint.

## ExportSurface

`Target.Module.ExportSurface` describes the loaded residual program entry/result
surface. V1 exposes one main entry: entry function index, argument count, result
ref, optional result schema ref, normal-form kind, and target label.

## ProgramPlan And ValueSchema Images

`ProgramPlanImage` is a canonical image summary of the validated residual
ProgramPlan: label, plan hash, IR hash, entry function index, function,
requirement, op, output, local, block, terminator, instruction, value-schema,
product-field, and sum-variant row counts. It is not a mutable VM API.

`ValueSchemaImage` summarizes schema rows, product fields, sum variants, scalar
codec refs, and diagnostic labels. It does not widen `ProgramValue`, add codecs,
or rely on native Zig type pointer identity.

## WorldSurface, Maps, And Certificates

Full modules carry deterministic sections for the target-neutral surface
artifacts: `WorldSurface`, `WorldPortTable`, `WorldValueTable`,
`WorldDispatchTable`, `SurfaceProfile`, replay-key recipe metadata, SourceMap,
TraceMap, EvidenceMap, EffectRow, NormalForm, Target.Certificate,
NormalizationTrace, and NormalizationCertificate where present.

Validation checks section fingerprints, manifest bindings, dependency closure,
required sections, and policy limits. Target certificates bind the residual plan
hash, `WorldSurface`, maps, normal form, effect row, and module import/export
surface fingerprints where present.

## ModuleGraph

`Target.Module.Graph` is the content-addressed dependency graph for the module
root, section refs, dependency refs, external dependency refs, import/export
refs, certificate refs, and missing dependency blockers. V1 uses it for
validation diagnostics and partial-module preflight; future linking can build on
the same graph without turning Boundary into a package manager.

## LoadedModule

`Target.Module.decode` returns a `LoadedModule`: a decoded, validated,
target-neutral inspection object with the manifest, validation report, import
surface entries, export surface, and projection helpers:

- `matchRequest`
- `worldPortForSite`
- `worldPortForId`
- `replayKeySeed`
- `sourceForPort`
- `traceForPortRequest`
- `evidenceForPort`
- `validateWorldSurfaceScope`
- `importForWorldPort`
- `exportMain`

`LoadedModule.Session` is present but fail-closed in V1. It reports
`error.UnsupportedLoadedExecution` rather than exposing raw mutable VM internals
or pretending that arbitrary loaded ProgramPlan execution is supported.

## Import Binding Check

`Target.Module.validateImportBindings` checks that every required WorldPort
import has a matching World binding by dense id/ref and payload/response refs.
Extra bindings are rejected unless policy permits them. The actual handler table
and ABI remain World-owned.

## Wire Transfer Scenarios

World receiving a full module:

1. receive bytes
2. call Boundary module decoder/validator
3. inspect ImportSurface, ExportSurface, WorldSurface, and value refs
4. bind local port implementations by `world_port_id` or WorldPort ref
5. use `LoadedModule` projections, and later `LoadedModule.Session` when a
   supported loaded execution subset exists
6. store transcript/timeline separately

World receiving a reference module:

1. receive reference bytes
2. validate against a local generated Target
3. compare target certificate, `WorldSurface`, and ProgramPlan fingerprints
4. run the local generated target while keeping timelines/transcripts separate

## Safety And Trust

Fingerprints are deterministic semantic witnesses, not signatures or
authorization. Image validation is structural and semantic validation, not a
cryptographic security layer. Hosts must apply size limits for untrusted bytes
and decide whether to trust or execute a target image. Signing, encryption,
identity, transport, storage, scheduling, ABI choice, host execution, and
timeline persistence belong to World/host.

Boundary module bytes can be stored anywhere by World or the host. Boundary does
not select a storage backend, integrate a database, define an Artifact API, or
manage package discovery. Storage systems, including immutable database
experiments, are outside this Boundary milestone.
