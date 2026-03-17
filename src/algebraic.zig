const engine = @import("internal/algebraic_engine.zig");

/// Define one closed-world abortive operation.
pub const AbortOp = engine.AbortOp;
/// Define one closed-world zero-or-one-resume choice operation.
pub const ChoiceOp = engine.ChoiceOp;
/// Define one closed-world resumptive transform operation.
pub const TransformOp = engine.TransformOp;

/// Build an abort handler specification for a declared abort op.
pub const handleAbort = engine.handleAbort;
/// Build a choice handler specification for a declared choice op.
pub const handleChoice = engine.handleChoice;
/// Build a transform handler specification for a declared transform op.
pub const handleTransform = engine.handleTransform;

/// Build a closed-world algebraic program over the existing one-shot prompt runtime.
pub fn Program(
    comptime Answer: type,
    comptime ops: anytype,
) type {
    return engine.Program(Answer, Answer, error{}, ops);
}

test {
    _ = engine;
}
