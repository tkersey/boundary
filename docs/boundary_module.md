# Certified Boundary Module

Boundary serializes the normalized semantic boundary as a module. World
serializes execution timelines and supplies the world.

`Program.BoundaryClosure.Elaboration.Target.Module` is the module namespace for a
Certified Boundary Target. It exposes `reference`, `fullImage`, `encode`,
`decode`, `validate`, `validationReport`, `compatibility`, `dependencyReport`,
`validateSelf`, `asLoadedModule`, `matchesReferenceImage`, `referenceSummary`,
and `validateReferenceAgainst` helpers on generated targets. The public package
root does not widen.

Boundary should make modules easy to inspect and validate. World should decide
how to bind and run them.

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
must supply. V2 imports are residual WorldPorts. Each import carries import id,
dense `world_port_id`, `WorldPort` ref, optional host-intrinsic ref, source
effect-shape ref, residual site index/fingerprint, payload, response, and result
value table ids, payload/response/result refs, mode, response kind, replay-key
recipe ref, symbolic name, required flag, and metadata hooks.

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
hash, `WorldSurface`, maps, normal form, and effect row. Module import/export
surface fingerprints are module-owned and are bound by the manifest plus section
refs rather than by the target certificate.

## ModuleGraph

`Target.Module.Graph` is the content-addressed dependency graph for the module
root, section refs, dependency refs, external dependency refs, import/export
refs, certificate refs, and missing dependency blockers. V1 exposes it as a
content-addressed planning artifact; future linking can build on the same graph
without turning Boundary into a package manager.

## LoadedModule

`Target.Module.decode` returns a `LoadedModule`: a decoded, validated,
target-neutral inspection object with the manifest, validation report, import
surface entries, export surface, and projection helpers. Consumers should use
helpers instead of reading section tables manually.

- `kind`
- `manifest`
- `moduleFingerprint`
- `targetLabel`
- `targetCertificateFingerprint`
- `worldSurfaceFingerprint`
- `normalFormKind`
- `programPlanHash`
- `sectionCount`
- `dependencyCount`
- `isReferenceOnly`
- `isFullModule`
- `isPartialModule`
- `matchRequest`
- `worldPortForSite`
- `worldPortForId`
- `replayKeySeedForScope`
- `sourceForPort`
- `traceForPortRequest`
- `evidenceForPort`
- `validateWorldSurfaceScope`
- `importForWorldPort`
- `exportMain`

## ImportSurface Projection Helpers

`loaded.imports()` returns the decoded import projection. `requiredImports`,
`optionalImports`, `importCount`, `importForWorldPortId`,
`importForResidualSite`, `importForWorldPortRef`, `importSymbolicName`,
`importValueRefs`, `importSourceShapeRef`, and `importWorldPortRef` expose the
World-facing binding data without requiring raw section parsing.

Each import projection carries import id, dense `world_port_id`, `WorldPort`
ref, source EffectShape ref, residual site index/fingerprint, payload, response,
and result value table ids, payload/response/result value refs, mode, response
kind, required/optional status, symbolic name, and replay-key recipe ref when
present.

## ExportSurface Projection Helpers

V1 has one main export. `mainExport`, `resultValueRef`, `argumentValueRefs`,
`entryFunctionRef`, and `exportNormalFormKind` expose the entry/result shape
directly from the loaded export surface.

## WorldSurface Projection Helpers

`worldPortForSite`, `worldPortForId`, `valueDescriptor`, `dispatchForSite`,
`sourceForPort`, `traceForWorldPort`, `evidenceForWorldPort`, and
`replayKeyRecipe` project facts already present in the module image. Missing
facts return absence; Boundary does not fabricate World table rows from a ref.

`LoadedModule.Session` is present but fail-closed in V1. It reports
`error.UnsupportedLoadedExecution` rather than exposing raw mutable VM internals
or pretending that arbitrary loaded ProgramPlan execution is supported.

## ModuleCompatibilityReport

`Target.Module.compatibility(bytes, options)` and
`loaded.compatibilityReport()` summarize whether the image is compatible with
the current Boundary module validator. The report records module kind,
compatible status, unknown required/optional sections, unsupported versions,
loaded-execution blockers, dependency blockers, limit blockers, warnings, and
blockers. It is deterministic validation metadata, not a trust claim.

## ValidationReport And Diagnostics

`Target.Module.validationReport(bytes, options)` is the non-throwing diagnostic
surface. Validation remains fail-closed: `validate` still rejects malformed
images, while `validationReport` explains the blocker with deterministic
`ValidationDiagnostic` entries. Diagnostics carry severity, error tag, optional
section kind/index/offset, expected/actual fingerprint where available,
optional dependency ref, diagnostic code, and summary.

## ValidationLimits

`Target.Module.ValidationLimits` defines reusable limit profiles:
`small_test`, `default_safe`, `large_local`, and `audit_only`. Options can pass
a profile or keep individual legacy limit fields. Exceeding a limit produces a
deterministic blocker instead of best-effort parsing.

## DependencyReport

`Target.Module.dependencyReport(bytes, provided_deps)` and
`loaded.dependencyReport()` report embedded, external, missing, satisfied, and
cyclic dependency counts plus whether the dependency closure is complete. V1
does not resolve dependencies from storage or a registry.

## ImportBindingReport

`Target.Module.validateImportBindings` checks that every required WorldPort
import has a matching World binding by dense id/ref and payload/response refs.
Extra bindings are rejected unless policy permits them. The actual handler table
and ABI remain World-owned.

`loaded.checkImportBindings(bindings)` returns an `ImportBindingReport` instead
of throwing. Bindings are target-neutral descriptors: world port id/ref,
payload/response refs, mode/response-kind hints, and required handling. They do
not contain handlers, credentials, URLs, file handles, model clients, or ABI
details.

## Why LoadedModule.Session Remains Fail-Closed

Loaded execution is intentionally not part of this pass. `LoadedModule.Session`
has no public mutable VM internals and still returns
`UnsupportedLoadedExecution`. The supported path today is inspect, validate,
project imports/exports, preflight bindings, then let World run the generated
target or its chosen ABI/runtime.

## What Still Belongs To World

World owns port handlers, concrete ABI, transport, storage, timeline
serialization, service discovery, scheduling, async runtime, host intrinsic
execution, signing/encryption, package management, and loaded execution
runtime. Boundary emits the normalized semantic boundary and explains the
semantic surface.

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
