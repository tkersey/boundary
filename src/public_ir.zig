const effect_ir = @import("effect_ir");
const public_lowering = @import("public_lowering");

/// Preserve the prior effect_ir namespace while layering public compile helpers on top.
pub const ControlMode = effect_ir.ControlMode;
pub const Transform = effect_ir.Transform;
pub const Choice = effect_ir.Choice;
pub const Abort = effect_ir.Abort;
pub const NormalizedLeaf = effect_ir.NormalizedLeaf;
pub const NormalizedRow = effect_ir.NormalizedRow;
pub const MergedRows = effect_ir.MergedRows;
pub const SymbolRef = effect_ir.SymbolRef;
pub const OutputSpec = effect_ir.OutputSpec;
pub const OpSpec = effect_ir.OpSpec;
pub const Requirement = effect_ir.Requirement;
pub const Row = effect_ir.Row;
pub const CallEdge = effect_ir.CallEdge;
pub const LocalId = effect_ir.LocalId;
pub const BlockId = effect_ir.BlockId;
pub const LocalCodec = effect_ir.LocalCodec;
pub const InstructionKind = effect_ir.InstructionKind;
pub const Instruction = effect_ir.Instruction;
pub const TerminatorKind = effect_ir.TerminatorKind;
pub const Terminator = effect_ir.Terminator;
pub const Block = effect_ir.Block;
pub const FunctionBody = effect_ir.FunctionBody;
pub const ResolverGraph = effect_ir.ResolverGraph;
pub const SccGroup = effect_ir.SccGroup;
pub const Function = effect_ir.Function;
pub const Program = effect_ir.Program;
pub const SccComponent = effect_ir.SccComponent;
pub const SccResolution = effect_ir.SccResolution;
pub const NormalizationDigest = effect_ir.NormalizationDigest;
pub const NormalizeError = effect_ir.NormalizeError;
pub const rowFromSpec = effect_ir.rowFromSpec;
pub const mergeRows = effect_ir.mergeRows;
pub const symbolIndex = effect_ir.symbolIndex;
pub const validateGraph = effect_ir.validateGraph;
pub const computeSccs = effect_ir.computeSccs;
pub const deinitSccs = effect_ir.deinitSccs;
pub const validateRow = effect_ir.validateRow;
pub const validateOutputs = effect_ir.validateOutputs;
pub const rowDigest = effect_ir.rowDigest;
pub const resolveSccs = effect_ir.resolveSccs;

fn Compile(comptime label: []const u8, comptime program: effect_ir.Program) type {
    return public_lowering.CompileIr(label, program);
}

/// Compile explicit public Effect IR into the same runtime-owned plan shape as explicit-path lowering.
pub const compile = Compile;
