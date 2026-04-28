const inner = @import("./agent_vm_artifact.zig");

/// Re-exported public ArtifactV1 surface for source-path consumers.
pub const ArtifactV1 = inner.ArtifactV1;
/// Re-exported capability operation descriptor.
pub const CapabilityOpV1 = inner.CapabilityOpV1;
/// Re-exported capability descriptor.
pub const CapabilityV1 = inner.CapabilityV1;
/// Re-exported host operation kind.
pub const HostOpKind = inner.HostOpKind;
/// Re-exported ArtifactV1 decoder.
pub const decode = inner.decode;
/// Re-exported ArtifactV1 decoder that also returns the validated runtime plan.
pub const decodeWithProgramPlan = inner.decodeWithProgramPlan;
/// Re-exported decoded ArtifactV1 plus validated runtime plan bundle.
pub const DecodedProgramPlanV1 = inner.DecodedProgramPlanV1;
/// Re-exported terminal result codec resolver.
pub const terminalResultCodecForOp = inner.terminalResultCodecForOp;
