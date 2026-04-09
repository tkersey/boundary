const shared = @import("shift_shared");
pub const bundle = @import("bundle_envelope_v1.zig");
pub const host_adapter = @import("host_adapter_v1.zig");
pub const runtime = @import("artifact_vm_runtime.zig");

pub const artifact = shared.artifact;
pub const ArtifactV1 = artifact.ArtifactV1;
pub const CapabilityManifestV1 = artifact.CapabilityManifestV1;
pub const CapabilityV1 = artifact.CapabilityV1;
pub const CapabilityOpV1 = artifact.CapabilityOpV1;
pub const CapabilityKind = artifact.CapabilityKind;
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
