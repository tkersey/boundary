const inner = @import("./internal/program_plan.zig");

/// Re-exported basic-block descriptor.
pub const BlockPlan = inner.BlockPlan;
/// Re-exported control mode tag.
pub const ControlMode = inner.ControlMode;
/// Re-exported function descriptor.
pub const FunctionPlan = inner.FunctionPlan;
/// Re-exported instruction descriptor.
pub const Instruction = inner.Instruction;
/// Re-exported instruction kind tag.
pub const InstructionKind = inner.InstructionKind;
/// Re-exported local descriptor.
pub const LocalPlan = inner.LocalPlan;
/// Re-exported operation descriptor.
pub const OpPlan = inner.OpPlan;
/// Re-exported output descriptor.
pub const OutputPlan = inner.OutputPlan;
/// Re-exported program plan.
pub const ProgramPlan = inner.ProgramPlan;
/// Re-exported requirement descriptor.
pub const RequirementPlan = inner.RequirementPlan;
/// Re-exported terminator descriptor.
pub const Terminator = inner.Terminator;
/// Re-exported terminator kind tag.
pub const TerminatorKind = inner.TerminatorKind;
/// Re-exported validation error set.
pub const ValidationError = inner.ValidationError;
/// Re-exported value codec tag.
pub const ValueCodec = inner.ValueCodec;
/// Re-exported value codec resolver.
pub const codecForType = inner.codecForType;
/// Re-exported function result codec resolver.
pub const functionResultCodec = inner.functionResultCodec;
/// Re-exported payload helper.
pub const hasPayload = inner.hasPayload;
/// Re-exported IR hash helper.
pub const irHashForProgram = inner.irHashForProgram;
/// Re-exported row-only plan lowering entrypoint.
pub const planFromProgram = inner.planFromProgram;
/// Re-exported legacy plan upgrader.
pub const upgradeLegacyProgramPlan = inner.upgradeLegacyProgramPlan;
