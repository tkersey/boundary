/// Exact-build bundle envelope helpers over ArtifactV1 bytes.
pub const bundle = @import("bundle_envelope_v1");
/// Typed HostAdapterV1 request/result/logging boundary.
pub const host_adapter = @import("host_adapter_v1");
/// Synchronous ArtifactV1 runtime execution over HostAdapterV1.
pub const runtime = @import("artifact_vm_runtime");
const shared = @import("shift_shared");

/// ArtifactV1 encoding and decoding helpers shared with `shift_compile`.
pub const artifact = shared.artifact;
/// Public ArtifactV1 binary representation.
pub const ArtifactV1 = artifact.ArtifactV1;
/// Public capability-manifest metadata carried by ArtifactV1.
pub const CapabilityManifestV1 = artifact.CapabilityManifestV1;
/// Public capability descriptor carried by ArtifactV1.
pub const CapabilityV1 = artifact.CapabilityV1;
/// Public capability-op descriptor carried by ArtifactV1.
pub const CapabilityOpV1 = artifact.CapabilityOpV1;
/// Public capability kind tag carried by ArtifactV1.
pub const CapabilityKind = artifact.CapabilityKind;
/// Public capability codec tag carried by ArtifactV1.
pub const CapabilityCodecV1 = artifact.CapabilityCodecV1;

/// Explicit compatibility namespace for the retained front-door runtime shell.
pub const compat = shared.compat;
/// Public durable session helpers over the interpreter core.
pub const durable = shared.durable;
/// Public explicit interpreter state and step helpers.
pub const interpreter = shared.interpreter;
/// Stable public error-witness schema.
pub const ErrorWitnessV1 = shared.ErrorWitnessV1;
/// Canonical runtime handle for explicit VM execution.
pub const Runtime = shared.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `shift_vm`.
pub const RuntimeError = shared.RuntimeError;
/// Public declaration namespace.
pub const Decl = shared.Decl;
/// Public op-descriptor namespace.
pub const Op = shared.Op;
/// Root-level choice-decision helper for the retained front-door API.
pub const Decision = shared.Decision;
/// Public program builder.
pub const Program = shared.Program;
/// Run one program with explicit runtime ownership and bindings.
pub const run = shared.run;

test {
    _ = ArtifactV1;
    _ = CapabilityCodecV1;
    _ = CapabilityKind;
    _ = CapabilityManifestV1;
    _ = CapabilityOpV1;
    _ = CapabilityV1;
    _ = Decision;
    _ = Decl;
    _ = ErrorWitnessV1;
    _ = Op;
    _ = Program;
    _ = Runtime;
    _ = RuntimeError;
    _ = artifact;
    _ = bundle;
    _ = compat;
    _ = durable;
    _ = host_adapter;
    _ = interpreter;
    _ = runtime;
    _ = run;
}
