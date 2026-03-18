const engine = @import("internal/algebraic_engine.zig");

fn ReturnTypeErrorSet(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.error_set,
        else => error{},
    };
}

fn SpecErrorSet(comptime SpecType: type) type {
    const Impl = SpecType.ImplType;
    return switch (SpecType.builder_kind) {
        .direct_transform, .transform => ReturnTypeErrorSet(@typeInfo(@TypeOf(Impl.resumeValue)).@"fn".return_type.?) ||
            ReturnTypeErrorSet(@typeInfo(@TypeOf(Impl.afterResume)).@"fn".return_type.?),
        .choice => ReturnTypeErrorSet(@typeInfo(@TypeOf(Impl.resumeOrReturn)).@"fn".return_type.?) ||
            ReturnTypeErrorSet(@typeInfo(@TypeOf(Impl.afterResume)).@"fn".return_type.?),
        .abort => ReturnTypeErrorSet(@typeInfo(@TypeOf(Impl.directReturn)).@"fn".return_type.?),
    };
}

fn SpecsErrorSet(comptime SpecsType: type) type {
    const fields = @typeInfo(SpecsType).@"struct".fields;
    var ErrorSet = error{};
    inline for (fields) |field| {
        ErrorSet = ErrorSet || SpecErrorSet(field.type);
    }
    return ErrorSet;
}

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

/// Build a closed-world algebraic program over the existing one-shot prompt runtime with an explicit error set.
pub fn ProgramWithErrorSet(
    comptime Answer: type,
    comptime ErrorSet: type,
    comptime ops: anytype,
) type {
    return engine.Program(Answer, Answer, ErrorSet, ops);
}

/// Build a closed-world algebraic program over the existing one-shot prompt runtime.
pub fn Program(
    comptime Answer: type,
    comptime ops: anytype,
) type {
    return struct {
        /// Bind one handler specification per declared operation in declaration order.
        pub fn handlers(specs: anytype) @TypeOf(ProgramWithErrorSet(Answer, SpecsErrorSet(@TypeOf(specs)), ops).handlers(specs)) {
            return ProgramWithErrorSet(Answer, SpecsErrorSet(@TypeOf(specs)), ops).handlers(specs);
        }
    };
}

test {
    _ = engine;
}
