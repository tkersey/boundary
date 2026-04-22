const effect_ir = @import("../effect_ir.zig");

/// Stable local slot identifier inside one helper body.
pub const LocalId = effect_ir.LocalId;

/// Stable basic-block identifier inside one helper body.
pub const BlockId = effect_ir.BlockId;

/// Stable local codec used by one helper body slot.
pub const LocalCodec = effect_ir.LocalCodec;

/// One internal helper-body terminator kind.
pub const TerminatorKind = effect_ir.TerminatorKind;

/// One internal helper-body instruction.
pub const Instruction = effect_ir.Instruction;

/// One internal helper-body terminator.
pub const Terminator = effect_ir.Terminator;

/// One internal helper-body basic block.
pub const Block = effect_ir.Block;

/// One internal helper-body payload aligned to one lowered function.
pub const FunctionBody = effect_ir.FunctionBody;
