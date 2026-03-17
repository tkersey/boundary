const engine = @import("internal/algebraic_engine.zig");
const prompt_contract = @import("prompt_contract_support");

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

fn methodErrorSet(comptime FnType: type) type {
    const ReturnType = @typeInfo(FnType).@"fn".return_type.?;
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.error_set,
        else => error{},
    };
}

fn specErrorSet(comptime SpecType: type, comptime Answer: type) type {
    const Impl = SpecType.ImplType;
    _ = Answer;
    return switch (SpecType.builder_kind) {
        .direct_transform, .transform => methodErrorSet(@TypeOf(Impl.resumeValue)) || methodErrorSet(@TypeOf(Impl.afterResume)),
        .choice => methodErrorSet(@TypeOf(Impl.resumeOrReturn)) || methodErrorSet(@TypeOf(Impl.afterResume)),
        .abort => methodErrorSet(@TypeOf(Impl.directReturn)),
    };
}

fn inferredProgramErrorSet(comptime SpecsTupleType: type, comptime Answer: type) type {
    const fields = @typeInfo(SpecsTupleType).@"struct".fields;
    var ErrorSet = error{};
    inline for (fields) |field| {
        ErrorSet = ErrorSet || specErrorSet(field.type, Answer);
    }
    return ErrorSet;
}

/// Compatibility engine-shaped algebraic program with an explicit ErrorSet generic.
pub fn ProgramWithErrorSet(
    comptime Answer: type,
    comptime ErrorSet: type,
    comptime ops: anytype,
) type {
    return engine.Program(Answer, Answer, ErrorSet, ops);
}

/// Build a closed-world algebraic program whose public error set is inferred from the installed handlers.
pub fn Program(
    comptime Answer: type,
    comptime ops: anytype,
) type {
    return struct {
        const program_ops = ops;

        pub fn handlers(specs: anytype) @TypeOf(ProgramWithErrorSet(Answer, inferredProgramErrorSet(@TypeOf(specs), Answer), program_ops).handlers(specs)) {
            return ProgramWithErrorSet(Answer, inferredProgramErrorSet(@TypeOf(specs), Answer), program_ops).handlers(specs);
        }
    };
}

test {
    _ = engine;
    _ = prompt_contract;
}
