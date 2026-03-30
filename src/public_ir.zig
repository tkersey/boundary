const effect_ir = @import("effect_ir");
const public_lowering = @import("public_lowering.zig");

/// Public explicit Effect IR program type.
pub const Program = effect_ir.Program;
/// Public explicit Effect IR row type.
pub const Row = effect_ir.Row;
/// Public explicit Effect IR symbol reference.
pub const SymbolRef = effect_ir.SymbolRef;
/// Public explicit Effect IR function descriptor.
pub const Function = effect_ir.Function;
/// Public explicit Effect IR output descriptor.
pub const OutputSpec = effect_ir.OutputSpec;
/// Public explicit Effect IR call-edge descriptor.
pub const CallEdge = effect_ir.CallEdge;
/// Public explicit Effect IR helper-body local codec.
pub const LocalCodec = effect_ir.LocalCodec;
/// Public explicit Effect IR helper-body instruction tag.
pub const InstructionKind = effect_ir.InstructionKind;
/// Public explicit Effect IR helper-body instruction.
pub const Instruction = effect_ir.Instruction;
/// Public explicit Effect IR helper-body terminator tag.
pub const TerminatorKind = effect_ir.TerminatorKind;
/// Public explicit Effect IR helper-body terminator.
pub const Terminator = effect_ir.Terminator;
/// Public explicit Effect IR helper-body block.
pub const Block = effect_ir.Block;
/// Public explicit Effect IR helper-body payload.
pub const FunctionBody = effect_ir.FunctionBody;
/// Public explicit transform-op descriptor constructor.
pub const Transform = effect_ir.Transform;
/// Public explicit choice-op descriptor constructor.
pub const Choice = effect_ir.Choice;
/// Public explicit abort-op descriptor constructor.
pub const Abort = effect_ir.Abort;
/// Public explicit Effect IR row constructor.
pub const rowFromSpec = effect_ir.rowFromSpec;
/// Public explicit Effect IR row merge helper.
pub const mergeRows = effect_ir.mergeRows;

fn Compile(comptime label: []const u8, comptime program: effect_ir.Program) type {
    return public_lowering.CompileIr(label, program);
}

/// Compile explicit public Effect IR into the same runtime-owned plan shape as explicit-path lowering.
pub const compile = Compile;
