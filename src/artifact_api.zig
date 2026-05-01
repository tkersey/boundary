const inner = @import("./agent_vm_artifact.zig");

/// Re-exported public ArtifactV1 surface for source-path consumers.
pub const ArtifactV1 = inner.ArtifactV1;
/// Re-exported capability operation descriptor.
pub const CapabilityOpV1 = inner.CapabilityOpV1;
/// Re-exported capability descriptor.
pub const CapabilityV1 = inner.CapabilityV1;
/// Re-exported host operation kind.
pub const HostOpKind = inner.HostOpKind;
/// Re-exported decode-time failure domain.
pub const DecodeError = inner.DecodeError;
/// Re-exported public decode result error set.
pub const DecodeResultError = inner.DecodeResultError;
/// Re-exported public decode resource envelope.
pub const DecodeOptions = inner.DecodeOptions;
/// Re-exported default decode byte budget.
pub const default_max_artifact_bytes = inner.default_max_artifact_bytes;
/// Re-exported ArtifactV1 decoder.
pub const decode = inner.decode;
/// Re-exported ArtifactV1 decoder with explicit resource bounds.
pub const decodeWithOptions = inner.decodeWithOptions;
/// Re-exported ArtifactV1 decoder that also returns the validated runtime plan.
pub const decodeWithProgramPlan = inner.decodeWithProgramPlan;
/// Re-exported ArtifactV1 decoder plus plan with explicit resource bounds.
pub const decodeWithProgramPlanOptions = inner.decodeWithProgramPlanOptions;
/// Re-exported decoded ArtifactV1 plus validated runtime plan bundle.
pub const DecodedProgramPlanV1 = inner.DecodedProgramPlanV1;
/// Re-exported terminal result codec resolver.
pub const terminalResultCodecForOp = inner.terminalResultCodecForOp;
/// Re-exported ProgramPlan capability derivation helper.
pub const deriveToolCapabilitiesFromPlan = inner.deriveToolCapabilitiesFromPlan;
/// Re-exported allocator cleanup for derived capability manifests.
pub const deepFreeCapabilities = inner.deepFreeCapabilities;
/// Re-exported ProgramPlan ArtifactV1 encoder.
pub const encodeProgramPlan = inner.encodeProgramPlan;
/// Re-exported ArtifactV1 disassembly renderer.
pub const disasmAlloc = inner.disasmAlloc;
