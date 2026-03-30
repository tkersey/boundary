const program_plan = @import("internal_program_plan");

/// Stable local slot identifier inside one helper body.
pub const LocalId = u16;

/// Stable basic-block identifier inside one helper body.
pub const BlockId = u16;

/// Stable local codec used by one helper body slot.
pub const LocalCodec = program_plan.ValueCodec;

/// One internal helper-body terminator kind.
pub const TerminatorKind = program_plan.TerminatorKind;

/// One internal helper-body instruction.
pub const Instruction = struct {
    kind: program_plan.InstructionKind,
    dst: LocalId = 0,
    operand: u16 = 0,
    aux: u16 = 0,
};

/// One internal helper-body terminator.
pub const Terminator = struct {
    kind: TerminatorKind,
    primary: u16 = 0,
    secondary: u16 = 0,
};

/// One internal helper-body basic block.
pub const Block = struct {
    instructions: []const Instruction,
    terminator: Terminator,
};

/// One internal helper-body payload aligned to one lowered function.
pub const FunctionBody = struct {
    local_codecs: []const LocalCodec = &.{},
    entry_block: BlockId = 0,
    blocks: []const Block = &.{},
};
