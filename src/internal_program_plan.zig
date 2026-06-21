const inner = @import("./internal/program_plan.zig");
const std = @import("std");

/// Re-exported basic-block descriptor.
pub const BlockPlan = inner.BlockPlan;
/// Re-exported control mode tag.
pub const ControlMode = inner.ControlMode;
/// Re-exported codec-selection error set.
pub const CodecError = inner.CodecError;
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
/// Re-exported internal program-plan construction kernel.
pub const program_plan_builder = inner.program_plan_builder;
/// Re-exported requirement descriptor.
pub const RequirementPlan = inner.RequirementPlan;
/// Re-exported requirement lifecycle semantics tag.
pub const RequirementLifecycleTag = inner.RequirementLifecycleTag;
/// Re-exported requirement output semantics tag.
pub const RequirementOutputTag = inner.RequirementOutputTag;
/// Re-exported terminator descriptor.
pub const Terminator = inner.Terminator;
/// Re-exported terminator kind tag.
pub const TerminatorKind = inner.TerminatorKind;
/// Re-exported validation error set.
pub const ValidationError = inner.ValidationError;
/// Re-exported value codec tag.
pub const ValueCodec = inner.ValueCodec;
/// Re-exported value codec plus optional schema reference.
pub const ValueRef = inner.ValueRef;
/// Re-exported product field descriptor.
pub const ValueFieldPlan = inner.ValueFieldPlan;
/// Re-exported value-schema descriptor.
pub const ValueSchemaPlan = inner.ValueSchemaPlan;
/// Re-exported sum variant descriptor.
pub const ValueVariantPlan = inner.ValueVariantPlan;
/// Re-exported value codec resolver.
pub const codecForType = inner.codecForType;
/// Re-exported value-schema derivation helper.
pub const ValueSchemaForType = inner.ValueSchemaForType;
/// Re-exported flat value-schema registry helper.
pub const ValueSchemaRegistryForTypes = inner.ValueSchemaRegistryForTypes;
/// Re-exported instruction aux codec decoder for executable diagnostics.
pub const valueCodecFromInstructionAux = inner.valueCodecFromInstructionAux;
/// Re-exported product-field count helper.
pub const fieldCountForType = inner.fieldCountForType;
/// Re-exported sum-variant count helper.
pub const variantCountForType = inner.variantCountForType;
/// Re-exported authored bound-plan construction helper.
pub const authoredBoundPlan = inner.authoredBoundPlan;
/// Re-exported function result codec resolver.
pub const functionResultCodec = inner.functionResultCodec;
/// Re-exported function result codec/schema resolver.
pub const functionResultRef = inner.functionResultRef;
/// Re-exported payload helper.
pub const hasPayload = inner.hasPayload;
/// Re-exported IR hash helper.
pub const irHashForProgram = inner.irHashForProgram;
/// Re-exported row-only plan lowering entrypoint.
pub const planFromProgram = inner.planFromProgram;
/// Re-exported permissive binding-schema metadata enrichment.
pub const enrichPlanWithBindingSchemas = inner.enrichPlanWithBindingSchemas;
/// Re-exported entry execution reachability analysis type.
pub const EntryExecutionAnalysis = inner.EntryExecutionAnalysis;
/// Re-exported entry execution reachability analysis.
pub const entryExecutionAnalysis = inner.entryExecutionAnalysis;
/// Re-exported entry execution reachability analysis with resolver-backed nested targets.
pub const entryExecutionAnalysisWithNestedTargets = inner.entryExecutionAnalysisWithNestedTargets;
/// Re-exported exact binding-schema metadata enrichment.
pub const enrichPlanWithBindingSchemasExact = inner.enrichPlanWithBindingSchemasExact;
/// Re-exported legacy plan upgrader.
pub const upgradeLegacyProgramPlan = inner.upgradeLegacyProgramPlan;

test {
    std.testing.refAllDecls(inner);
}
