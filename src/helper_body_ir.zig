const inner = @import("./internal/helper_body_ir.zig");

/// Re-exported helper-body block descriptor.
pub const Block = inner.Block;
/// Re-exported helper-body block identifier.
pub const BlockId = inner.BlockId;
/// Re-exported helper-body payload.
pub const FunctionBody = inner.FunctionBody;
/// Re-exported helper-body instruction descriptor.
pub const Instruction = inner.Instruction;
/// Re-exported helper-body local codec.
pub const LocalCodec = inner.LocalCodec;
/// Re-exported helper-body local identifier.
pub const LocalId = inner.LocalId;
/// Re-exported helper-body terminator descriptor.
pub const Terminator = inner.Terminator;
/// Re-exported helper-body terminator kind.
pub const TerminatorKind = inner.TerminatorKind;
