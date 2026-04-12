/// Retained internal exact-build bundle envelope helpers over ArtifactV1 bytes.
pub const bundle = @import("bundle_envelope_v1");
/// Retained internal HostAdapterV1 request/result/logging boundary.
pub const host_adapter = @import("host_adapter_v1");
/// Retained internal synchronous ArtifactV1 runtime execution over HostAdapterV1.
pub const runtime = @import("artifact_vm_runtime");
const shared = @import("shift_shared");

/// Retained internal ArtifactV1 encoding and decoding helpers shared with `shift_compile`.
pub const artifact = shared.artifact;
/// Retained internal ArtifactV1 binary representation.
pub const ArtifactV1 = artifact.ArtifactV1;
/// Retained internal capability-manifest metadata carried by ArtifactV1.
pub const CapabilityManifestV1 = artifact.CapabilityManifestV1;
/// Retained internal capability descriptor carried by ArtifactV1.
pub const CapabilityV1 = artifact.CapabilityV1;
/// Retained internal capability-op descriptor carried by ArtifactV1.
pub const CapabilityOpV1 = artifact.CapabilityOpV1;
/// Retained internal capability kind tag carried by ArtifactV1.
pub const CapabilityKind = artifact.CapabilityKind;
/// Retained internal capability codec tag carried by ArtifactV1.
pub const CapabilityCodecV1 = artifact.CapabilityCodecV1;

/// Retained internal compatibility namespace for the old front-door runtime shell.
pub const compat = shared.compat;
/// Retained internal durable session helpers over the interpreter core.
pub const durable = shared.durable;
/// Retained internal explicit interpreter state and step helpers.
pub const interpreter = shared.interpreter;
/// Retained internal error-witness schema.
pub const ErrorWitnessV1 = shared.ErrorWitnessV1;
/// Retained internal runtime handle for explicit VM execution.
pub const Runtime = shared.Runtime;
/// Retained internal runtime misuse and semantic-contract errors surfaced by `shift_vm`.
pub const RuntimeError = shared.RuntimeError;
/// Retained internal declaration namespace.
pub const Decl = shared.Decl;
/// Retained internal op-descriptor namespace.
pub const Op = shared.Op;
/// Retained internal choice-decision helper for the old explicit front-door API.
pub const Decision = shared.Decision;
/// Retained internal program builder.
pub const Program = shared.Program;
/// Retained internal explicit program runner.
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
