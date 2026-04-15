const choice = @import("choice.zig");
const effect_schema = @import("../effect_schema.zig");
const family = @import("family.zig");
const frontend = @import("frontend_support");
const internal = @import("../internal/algebraic_engine.zig");
const lexical_with = @import("../with_api.zig");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const sealed_engine = @import("../internal/sealed_engine.zig");
const shift = lowered_machine;
const std = @import("std");

/// Stable compile-time manifest for one generated effect family.
pub fn Definition(comptime OpTag: type) type {
    _ = OpTag;
    return struct {
        mode: prompt_contract.PromptMode,
        StateType: type,
        ErrorSetType: type,
        OpTagType: type,
        op_count: usize,
    };
}

/// Public op-descriptor namespace used by `shift.effect.Define(...)`.
pub const ops = struct {
    /// Define one sealed transform op descriptor for a generated family.
    pub fn Transform(
        comptime name: [:0]const u8,
        comptime PayloadType: type,
        comptime ResumeType: type,
    ) type {
        return struct {
            /// The comptime name of this generated op.
            pub const op_name: [:0]const u8 = name;
            /// The prompt mode used by this generated op.
            pub const mode = prompt_contract.PromptMode.resume_then_transform;
            /// The payload type accepted by this generated op.
            pub const Payload = PayloadType;
            /// The resumptive return type produced by this generated op.
            pub const Resume = ResumeType;
        };
    }
    /// Define one sealed choice op descriptor for a generated family.
    pub fn Choice(
        comptime name: [:0]const u8,
        comptime PayloadType: type,
        comptime ResumeType: type,
    ) type {
        return struct {
            /// The comptime name of this generated op.
            pub const op_name: [:0]const u8 = name;
            /// The prompt mode used by this generated op.
            pub const mode = prompt_contract.PromptMode.resume_or_return;
            /// The payload type accepted by this generated op.
            pub const Payload = PayloadType;
            /// The resumptive return type produced by this generated op.
            pub const Resume = ResumeType;
        };
    }
    /// Define one sealed abort op descriptor for a generated family.
    pub fn Abort(
        comptime name: [:0]const u8,
        comptime PayloadType: type,
    ) type {
        return struct {
            /// The comptime name of this generated op.
            pub const op_name: [:0]const u8 = name;
            /// The prompt mode used by this generated op.
            pub const mode = prompt_contract.PromptMode.direct_return;
            /// The payload type accepted by this generated op.
            pub const Payload = PayloadType;
            /// The terminal return marker for this generated abort op.
            pub const Resume = noreturn;
        };
    }
};

fn afterMethodName(comptime op_name: []const u8) []const u8 {
    var buffer: [128]u8 = undefined;
    var len: usize = 0;
    buffer[len..][0..5].* = "after".*;
    len += 5;
    var upper_next = true;
    inline for (op_name) |byte| {
        if (byte == '_') {
            upper_next = true;
            continue;
        }
        buffer[len] = if (upper_next and byte >= 'a' and byte <= 'z') byte - 32 else byte;
        len += 1;
        upper_next = false;
    }
    return buffer[0..len];
}

fn opName(comptime Op: type) [:0]const u8 {
    return Op.op_name;
}
fn opMode(comptime Op: type) prompt_contract.PromptMode {
    return Op.mode;
}
fn OpPayloadType(comptime Op: type) type {
    return Op.Payload;
}
fn OpResumeType(comptime Op: type) type {
    return Op.Resume;
}

fn ContinuationCarrierType(comptime Continuation: anytype) type {
    return if (@TypeOf(Continuation) == type) Continuation else @TypeOf(Continuation);
}

fn continuationHasApply(comptime Continuation: anytype) bool {
    return family.hasDeclSafe(ContinuationCarrierType(Continuation), "apply");
}

fn returnTypeMatches(comptime ReturnType: type, comptime ExpectedType: type) bool {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload == ExpectedType,
        else => ReturnType == ExpectedType,
    };
}

fn ReturnTypeErrorSet(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.error_set,
        else => error{},
    };
}

fn ExplicitContinuationFnType(comptime Continuation: anytype) type {
    const Carrier = ContinuationCarrierType(Continuation);
    if (continuationHasApply(Continuation)) return @TypeOf(Continuation.apply);
    return switch (@typeInfo(Carrier)) {
        .@"fn" => Carrier,
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn")
            pointer.child
        else
            @compileError("generated explicit program continuation must declare apply(value) or be a callable function"),
        else => @compileError("generated explicit program continuation must declare apply(value) or be a callable function"),
    };
}

fn ExplicitContinuationReturnType(comptime Continuation: anytype, comptime ResumeType: type) type {
    const ContinuationFn = ExplicitContinuationFnType(Continuation);
    const params = @typeInfo(ContinuationFn).@"fn".params;
    if (params.len != 1) @compileError("generated explicit program continuation must accept exactly one resumed value");
    if (comptime continuationHasApply(Continuation)) {
        return @TypeOf(Continuation.apply(dummyValue(ResumeType)));
    }
    if (comptime @TypeOf(Continuation) == type) @compileError("generated explicit-program continuations must be passed as callable values, not function types");
    return @TypeOf(Continuation(dummyValue(ResumeType)));
}

fn ExplicitContinuationAnswerType(comptime Continuation: anytype, comptime ResumeType: type) type {
    const ReturnType = ExplicitContinuationReturnType(Continuation, ResumeType);
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

fn ExplicitContinuationErrorSet(comptime Continuation: anytype, comptime ResumeType: type) type {
    return ReturnTypeErrorSet(ExplicitContinuationReturnType(Continuation, ResumeType));
}

fn fnParamsMatch(comptime FnType: type, comptime ParamTypes: []const type) bool {
    const actual = @typeInfo(FnType).@"fn".params;
    if (actual.len != ParamTypes.len) return false;
    inline for (ParamTypes, 0..) |ParamType, index| {
        if (actual[index].type == null or actual[index].type.? != ParamType) return false;
    }
    return true;
}

fn assertSpecShape(comptime SpecType: type) void {
    if (!@hasField(SpecType, "state_type")) @compileError("generated effect spec must declare state_type");
    if (!@hasField(SpecType, "ops")) @compileError("generated effect spec must declare ops");
}

fn inferMode(comptime op_specs: anytype) prompt_contract.PromptMode {
    if (op_specs.len == 0) @compileError("generated effect families must declare at least one op");
    const mode = opMode(op_specs[0]);
    inline for (op_specs, 0..) |Op, index| {
        if (index == 0) continue;
        if (opMode(Op) != mode) {
            @compileError("generated effect families support one prompt mode per family");
        }
    }
    return mode;
}

fn isIdentifierStart(byte: u8) bool {
    return (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or byte == '_';
}

fn isIdentifierContinue(byte: u8) bool {
    return isIdentifierStart(byte) or (byte >= '0' and byte <= '9');
}

fn assertValidIdentifier(comptime name: []const u8) void {
    if (name.len == 0 or !isIdentifierStart(name[0])) {
        @compileError("generated effect op names must be valid Zig identifiers");
    }
    inline for (name[1..]) |byte| {
        if (!isIdentifierContinue(byte)) {
            @compileError("generated effect op names must be valid Zig identifiers");
        }
    }
}

fn assertReservedName(comptime name: []const u8) void {
    inline for ([_][]const u8{
        "Instance",
        "HandleResult",
        "OpTag",
        "definition",
        "computeProgram",
        "handle",
        "op",
        "proof",
    }) |reserved| {
        if (comptime std.mem.eql(u8, name, reserved)) {
            @compileError("generated effect op name collides with reserved family export");
        }
    }
}

fn assertDescriptor(comptime mode: prompt_contract.PromptMode, comptime Op: type) void {
    if (opMode(Op) != mode) @compileError("generated effect families support one prompt mode per family");
    assertValidIdentifier(opName(Op));
    assertReservedName(opName(Op));
}

fn assertUniqueNames(comptime op_specs: anytype) void {
    inline for (op_specs, 0..) |Op, index| {
        inline for (op_specs, 0..) |Other, other_index| {
            if (other_index <= index) continue;
            if (comptime std.mem.eql(u8, opName(Op), opName(Other))) {
                @compileError("generated effect op names must be unique");
            }
        }
    }
}

fn BuildTagType(comptime op_specs: anytype) type {
    var fields = [_]std.builtin.Type.EnumField{.{ .name = "", .value = 0 }} ** op_specs.len;
    inline for (op_specs, 0..) |Op, index| {
        fields[index] = .{
            .name = opName(Op),
            .value = index,
        };
    }
    return @Type(.{
        .@"enum" = .{
            .tag_type = std.math.IntFittingRange(0, op_specs.len - 1),
            .fields = &fields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
}

fn buildDefinition(comptime OpTag: type, comptime StateType: type, comptime ErrorSetType: type, comptime mode: prompt_contract.PromptMode, comptime op_specs: anytype) Definition(OpTag) {
    return .{
        .mode = mode,
        .StateType = StateType,
        .ErrorSetType = ErrorSetType,
        .OpTagType = OpTag,
        .op_count = op_specs.len,
    };
}

fn opIndex(comptime op_specs: anytype, comptime tag: anytype) usize {
    inline for (op_specs, 0..) |Op, index| {
        if (tag == @field(@TypeOf(tag), opName(Op))) return index;
    }
    @compileError("generated effect family does not include the requested op tag");
}

fn OpType(comptime op_specs: anytype, comptime tag: anytype) type {
    return op_specs[opIndex(op_specs, tag)];
}

fn dummyPointer(comptime PtrType: type) PtrType {
    const pointer = @typeInfo(PtrType).pointer;
    const Child = std.meta.Child(PtrType);
    return switch (pointer.size) {
        .slice => blk: {
            const base = std.mem.alignForward(usize, 1, @alignOf(Child));
            const many = @as([*]Child, @ptrFromInt(base));
            const slice = many[0..1];
            if (pointer.is_const) break :blk @as(PtrType, slice);
            break :blk @as(PtrType, @constCast(slice));
        },
        else => @as(PtrType, @ptrFromInt(std.mem.alignForward(usize, 1, @alignOf(Child)))),
    };
}

fn dummyValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .pointer => dummyPointer(T),
        .optional => |optional| dummyValue(optional.child),
        .@"struct" => |info| blk: {
            var value_buffer: T = undefined;
            inline for (info.fields) |field| {
                @field(value_buffer, field.name) = dummyValue(field.type);
            }
            break :blk value_buffer;
        },
        .void => {},
        else => dummyPointer(*T).*,
    };
}

fn isEmptyStructType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| info.fields.len == 0,
        else => false,
    };
}

fn stateTypeProducesOutput(comptime T: type) bool {
    return T != void and !isEmptyStructType(T);
}

fn defaultStatelessStateValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .void => {},
        .@"struct" => .{},
        else => @compileError("stateless generated transform state must be void or an empty struct"),
    };
}

fn assertTransformHandlerBundle(comptime HandlerType: type, comptime StateType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime Op: type) void {
    _ = ErrorSetType;
    if (!@hasField(HandlerType, "state")) {
        if (stateTypeProducesOutput(StateType)) @compileError("generated transform handler must declare state");
    } else if (@FieldType(HandlerType, "state") != StateType) {
        @compileError("generated transform handler state field must match state_type");
    }
    if (!@hasDecl(HandlerType, opName(Op))) @compileError("generated transform handler is missing op method");

    const ResumeFn = @TypeOf(@field(HandlerType, opName(Op)));
    if (comptime OpPayloadType(Op) == void) {
        if (!fnParamsMatch(ResumeFn, &.{*HandlerType}) or !returnTypeMatches(HandlerReturnType(HandlerType, Op), OpResumeType(Op))) {
            @compileError("generated transform handler op method must have type fn (*Handler) Resume or fn (*Handler) ResetError(ErrorSet)!Resume");
        }
    } else {
        if (!fnParamsMatch(ResumeFn, &.{ *HandlerType, OpPayloadType(Op) }) or !returnTypeMatches(HandlerReturnType(HandlerType, Op), OpResumeType(Op))) {
            @compileError("generated transform handler op method must have type fn (*Handler, Payload) Resume or fn (*Handler, Payload) ResetError(ErrorSet)!Resume");
        }
    }

    const after_name = comptime afterMethodName(opName(Op));
    if (!@hasDecl(HandlerType, after_name)) return;
    const AfterFn = @TypeOf(@field(HandlerType, after_name));
    if (!fnParamsMatch(AfterFn, &.{ *HandlerType, AnswerType }) or !returnTypeMatches(AfterHandlerReturnType(HandlerType, Op), AnswerType)) {
        @compileError("generated transform handler after_<op> must have type fn (*Handler, Answer) Answer or fn (*Handler, Answer) ResetError(ErrorSet)!Answer");
    }
}

fn assertChoiceHandlerBundle(comptime HandlerType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime Op: type) void {
    _ = ErrorSetType;
    if (!@hasDecl(HandlerType, opName(Op))) @compileError("generated choice handler is missing op method");
    const DecisionType = choice.Decision(OpResumeType(Op), AnswerType);
    const ResumeFn = @TypeOf(@field(HandlerType, opName(Op)));
    if (comptime OpPayloadType(Op) == void) {
        if (!fnParamsMatch(ResumeFn, &.{*HandlerType}) or !returnTypeMatches(HandlerReturnType(HandlerType, Op), DecisionType)) {
            @compileError("generated choice handler op method must have type fn (*Handler) effect.choice.Decision or fn (*Handler) ResetError(ErrorSet)!effect.choice.Decision");
        }
    } else {
        if (!fnParamsMatch(ResumeFn, &.{ *HandlerType, OpPayloadType(Op) }) or !returnTypeMatches(HandlerReturnType(HandlerType, Op), DecisionType)) {
            @compileError("generated choice handler op method must have type fn (*Handler, Payload) effect.choice.Decision or fn (*Handler, Payload) ResetError(ErrorSet)!effect.choice.Decision");
        }
    }

    const after_name = comptime afterMethodName(opName(Op));
    if (!@hasDecl(HandlerType, after_name)) return;
    const AfterFn = @TypeOf(@field(HandlerType, after_name));
    if (!fnParamsMatch(AfterFn, &.{ *HandlerType, AnswerType }) or !returnTypeMatches(AfterHandlerReturnType(HandlerType, Op), AnswerType)) {
        @compileError("generated choice handler after_<op> must have type fn (*Handler, Answer) Answer or fn (*Handler, Answer) ResetError(ErrorSet)!Answer");
    }
}

fn assertAbortHandlerBundle(comptime HandlerType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime Op: type) void {
    _ = ErrorSetType;
    if (!@hasDecl(HandlerType, opName(Op))) @compileError("generated abort handler is missing op method");
    const DirectFn = @TypeOf(@field(HandlerType, opName(Op)));
    if (comptime OpPayloadType(Op) == void) {
        if (!fnParamsMatch(DirectFn, &.{*HandlerType}) or !returnTypeMatches(HandlerReturnType(HandlerType, Op), AnswerType)) {
            @compileError("generated abort handler op method must have type fn (*Handler) Answer or fn (*Handler) ResetError(ErrorSet)!Answer");
        }
    } else {
        if (!fnParamsMatch(DirectFn, &.{ *HandlerType, OpPayloadType(Op) }) or !returnTypeMatches(HandlerReturnType(HandlerType, Op), AnswerType)) {
            @compileError("generated abort handler op method must have type fn (*Handler, Payload) Answer or fn (*Handler, Payload) ResetError(ErrorSet)!Answer");
        }
    }
}

fn assertHandlerBundle(comptime mode: prompt_contract.PromptMode, comptime StateType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime op_specs: anytype, comptime HandlerType: type) void {
    inline for (op_specs) |Op| {
        switch (mode) {
            .resume_then_transform => assertTransformHandlerBundle(HandlerType, StateType, AnswerType, ErrorSetType, Op),
            .resume_or_return => assertChoiceHandlerBundle(HandlerType, AnswerType, ErrorSetType, Op),
            .direct_return => assertAbortHandlerBundle(HandlerType, AnswerType, ErrorSetType, Op),
        }
    }
}

fn HandlerReturnType(comptime HandlerType: type, comptime Op: type) type {
    const handler_method = @field(HandlerType, opName(Op));
    return if (comptime OpPayloadType(Op) == void)
        @TypeOf(handler_method(dummyPointer(*HandlerType)))
    else
        @TypeOf(handler_method(dummyPointer(*HandlerType), dummyValue(OpPayloadType(Op))));
}

fn AfterHandlerAnswerType(comptime HandlerType: type, comptime Op: type) type {
    const AfterFn = @TypeOf(@field(HandlerType, afterMethodName(opName(Op))));
    return @typeInfo(AfterFn).@"fn".params[1].type.?;
}

fn AfterHandlerReturnType(comptime HandlerType: type, comptime Op: type) type {
    return @TypeOf(@field(HandlerType, afterMethodName(opName(Op)))(
        dummyPointer(*HandlerType),
        dummyValue(AfterHandlerAnswerType(HandlerType, Op)),
    ));
}

fn InferHandlerErrorSet(
    comptime mode: prompt_contract.PromptMode,
    comptime op_specs: anytype,
    comptime HandlerType: type,
) type {
    comptime @setEvalBranchQuota(20_000);
    var ErrorSet = error{};
    inline for (op_specs) |Op| {
        switch (mode) {
            .resume_then_transform => {
                const ResumeReturnType = HandlerReturnType(HandlerType, Op);
                ErrorSet = ErrorSet ||
                    ReturnTypeErrorSet(ResumeReturnType);
                if (@hasDecl(HandlerType, afterMethodName(opName(Op)))) {
                    const AfterReturnType = AfterHandlerReturnType(HandlerType, Op);
                    ErrorSet = ErrorSet || ReturnTypeErrorSet(AfterReturnType);
                }
            },
            .resume_or_return => {
                const DecideReturnType = HandlerReturnType(HandlerType, Op);
                ErrorSet = ErrorSet ||
                    ReturnTypeErrorSet(DecideReturnType);
                if (@hasDecl(HandlerType, afterMethodName(opName(Op)))) {
                    const AfterReturnType = AfterHandlerReturnType(HandlerType, Op);
                    ErrorSet = ErrorSet || ReturnTypeErrorSet(AfterReturnType);
                }
            },
            .direct_return => {
                const DirectReturnType = HandlerReturnType(HandlerType, Op);
                ErrorSet = ErrorSet || ReturnTypeErrorSet(DirectReturnType);
            },
        }
    }
    return ErrorSet;
}

fn InferHandlerOperationErrorSet(
    comptime mode: prompt_contract.PromptMode,
    comptime op_specs: anytype,
    comptime HandlerType: type,
) type {
    comptime @setEvalBranchQuota(20_000);
    var ErrorSet = error{};
    inline for (op_specs) |Op| {
        const OperationReturnType = switch (mode) {
            .resume_then_transform, .resume_or_return, .direct_return => HandlerReturnType(HandlerType, Op),
        };
        ErrorSet = ErrorSet || ReturnTypeErrorSet(OperationReturnType);
        switch (mode) {
            .resume_then_transform, .resume_or_return => {
                if (@hasDecl(HandlerType, afterMethodName(opName(Op)))) {
                    const AfterReturnType = AfterHandlerReturnType(HandlerType, Op);
                    ErrorSet = ErrorSet || ReturnTypeErrorSet(AfterReturnType);
                }
            },
            .direct_return => {},
        }
    }
    return ErrorSet;
}

fn PreviewBodyErrorSet(
    comptime StateType: type,
    comptime AnswerType: type,
    comptime BaseErrorSet: type,
    comptime mode: prompt_contract.PromptMode,
    comptime Body: type,
) type {
    const preview_engine = struct {
        /// Perform this public operation.
        pub fn perform(_: *@This(), comptime Op: type, _: Op.Payload) lowered_machine.ResetError(BaseErrorSet)!Op.Resume {
            unreachable;
        }

        /// Build this public explicit program.
        pub fn performProgram(
            _: *@This(),
            comptime Op: type,
            _: Op.Payload,
            comptime Continuation: anytype,
        ) frontend.BoundProgram(prompt_contract.Prompt(
            Op.mode,
            Op.Resume,
            ExplicitContinuationAnswerType(Continuation, Op.Resume),
            BaseErrorSet || ExplicitContinuationErrorSet(Continuation, Op.Resume),
        )) {
            unreachable;
        }

        /// Build this public explicit program with one runtime continuation context.
        pub fn performProgramWithContext(
            _: *@This(),
            comptime Op: type,
            _: Op.Payload,
            _: anytype,
            comptime Continuation: type,
        ) frontend.BoundProgram(prompt_contract.Prompt(
            Op.mode,
            Op.Resume,
            switch (@typeInfo(@TypeOf(Continuation.apply(dummyValue(@typeInfo(@TypeOf(Continuation.apply)).@"fn".params[0].type.?), dummyValue(Op.Resume))))) {
                .error_union => |err_union| err_union.payload,
                else => @TypeOf(Continuation.apply(dummyValue(@typeInfo(@TypeOf(Continuation.apply)).@"fn".params[0].type.?), dummyValue(Op.Resume))),
            },
            BaseErrorSet || ReturnTypeErrorSet(@TypeOf(Continuation.apply(dummyValue(@typeInfo(@TypeOf(Continuation.apply)).@"fn".params[0].type.?), dummyValue(Op.Resume)))),
        )) {
            unreachable;
        }
    };

    const preview_capability = struct {
        /// Return the engine context type for this public helper.
        pub fn EngineContextType() type {
            return preview_engine;
        }
    };

    const PreviewContext = *family.Context(preview_capability, StateType, AnswerType, BaseErrorSet);
    _ = mode;
    if (family.hasDeclSafe(Body, "program")) {
        const AuthoredType = @TypeOf(Body.program(preview_capability, dummyValue(PreviewContext)));
        switch (@typeInfo(AuthoredType)) {
            .@"struct" => if (@hasField(AuthoredType, "prompt")) {
                return switch (@typeInfo(@FieldType(AuthoredType, "prompt"))) {
                    .pointer => |pointer| if (@hasDecl(pointer.child, "ErrorSet")) pointer.child.ErrorSet else error{},
                    else => error{},
                };
            },
            else => {},
        }
        return error{};
    }
    if (!family.hasDeclSafe(Body, "body")) return error{};
    return ReturnTypeErrorSet(@TypeOf(Body.body(preview_capability, dummyValue(PreviewContext))));
}

fn promptIdentity(prompt: anytype) *const anyopaque {
    return @ptrCast(prompt);
}

/// Build one sealed generated effect family from a declarative comptime spec.
pub fn Build(comptime spec: anytype) type {
    const SpecType = @TypeOf(spec);
    comptime @setEvalBranchQuota(20_000);
    comptime assertSpecShape(SpecType);
    const StateType: type = spec.state_type;
    const ErrorSetType: type = if (@hasField(SpecType, "error_set_type")) spec.error_set_type else error{};
    const op_specs = spec.ops;
    const inferred_mode = comptime inferMode(op_specs);
    const mode: prompt_contract.PromptMode = if (@hasField(SpecType, "mode")) blk: {
        if (spec.mode != inferred_mode) {
            @compileError("generated effect explicit mode must match inferred op mode");
        }
        break :blk spec.mode;
    } else inferred_mode;
    comptime {
        if (op_specs.len == 0) @compileError("generated effect families must declare at least one op");
        if (op_specs.len > 8) @compileError("generated effect families currently support at most 8 ops");
        for (op_specs) |Op| assertDescriptor(mode, Op);
        assertUniqueNames(op_specs);
    }
    const GeneratedOpTag = comptime BuildTagType(op_specs);
    const family_definition = comptime buildDefinition(GeneratedOpTag, StateType, ErrorSetType, mode, op_specs);

    return struct {
        const self_type = @This();
        /// Stable enum of generated operation tags.
        pub const OpTag = GeneratedOpTag;
        /// Stable compile-time manifest for this generated family.
        pub const definition = family_definition;
        /// Shared effect schema for this generated family definition.
        pub fn Schema() type {
            return effect_schema.generated_family(spec);
        }
        /// Prompt-sized instance shell for this generated family.
        pub const Instance = family.InstanceWithMode(mode, StateType, ErrorSetType);

        /// Final state plus answer wrapper for generated transform families.
        pub fn HandleResult(comptime AnswerType: type) type {
            if (mode != .resume_then_transform) @compileError("generated effect HandleResult only exists for transform families");
            return family.HandleResult(StateType, AnswerType);
        }

        /// Build one explicit generated-family body program with no operation.
        pub fn computeProgram(comptime Cap: type, ctx: anytype, thunk: anytype) frontend.Program(prompt_contract.Prompt(mode, family.ContextAnswerType(@TypeOf(ctx)), family.ContextAnswerType(@TypeOf(ctx)), family.ContextErrorSetType(@TypeOf(ctx)))) {
            comptime family.assertContextType(Cap, @TypeOf(ctx));
            const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
            const FamilyPrompt = prompt_contract.Prompt(mode, ContextType.AnswerType, ContextType.AnswerType, ContextType.ErrorSetType);
            return sealed_engine.computeProgramForPrompt(Cap, ctx, FamilyPrompt, thunk);
        }

        fn GeneratedImplType(comptime AnswerType: type, comptime RunErrorSetType: type, comptime HandlerPtrType: type, comptime index: usize) type {
            const HandlerType = std.meta.Child(HandlerPtrType);
            const op_type = op_specs[index];
            return switch (mode) {
                .resume_then_transform => struct {
                    /// Produce one resumptive value from the generated handler bundle.
                    pub fn resumeValue(self: HandlerPtrType, payload: OpPayloadType(op_type)) lowered_machine.ResetError(RunErrorSetType)!OpResumeType(op_type) {
                        const ResumeReturnType = HandlerReturnType(HandlerType, op_type);
                        if (comptime OpPayloadType(op_type) == void) {
                            if (comptime ReturnTypeErrorSet(ResumeReturnType) == error{}) return @field(HandlerType, opName(op_type))(self);
                            return try @field(HandlerType, opName(op_type))(self);
                        }
                        if (comptime ReturnTypeErrorSet(ResumeReturnType) == error{}) return @field(HandlerType, opName(op_type))(self, payload);
                        return try @field(HandlerType, opName(op_type))(self, payload);
                    }

                    /// Convert one resumed answer into the enclosing generated answer.
                    pub fn afterResume(self: HandlerPtrType, answer: AnswerType) lowered_machine.ResetError(RunErrorSetType)!AnswerType {
                        const after_name = comptime afterMethodName(opName(op_type));
                        if (!@hasDecl(HandlerType, after_name)) return answer;
                        const AfterReturnType = AfterHandlerReturnType(HandlerType, op_type);
                        if (comptime ReturnTypeErrorSet(AfterReturnType) == error{}) return @field(HandlerType, after_name)(self, answer);
                        return try @field(HandlerType, after_name)(self, answer);
                    }
                },
                .resume_or_return => struct {
                    /// Decide whether one generated choice op resumes or returns now.
                    pub fn resumeOrReturn(self: HandlerPtrType, payload: OpPayloadType(op_type)) lowered_machine.ResetError(RunErrorSetType)!choice.Decision(OpResumeType(op_type), AnswerType) {
                        const ResumeReturnType = HandlerReturnType(HandlerType, op_type);
                        if (comptime OpPayloadType(op_type) == void) {
                            if (comptime ReturnTypeErrorSet(ResumeReturnType) == error{}) return @field(HandlerType, opName(op_type))(self);
                            return try @field(HandlerType, opName(op_type))(self);
                        }
                        if (comptime ReturnTypeErrorSet(ResumeReturnType) == error{}) return @field(HandlerType, opName(op_type))(self, payload);
                        return try @field(HandlerType, opName(op_type))(self, payload);
                    }

                    /// Convert one resumed choice answer into the enclosing generated answer.
                    pub fn afterResume(self: HandlerPtrType, answer: AnswerType) lowered_machine.ResetError(RunErrorSetType)!AnswerType {
                        const after_name = comptime afterMethodName(opName(op_type));
                        if (!@hasDecl(HandlerType, after_name)) return answer;
                        const AfterReturnType = AfterHandlerReturnType(HandlerType, op_type);
                        if (comptime ReturnTypeErrorSet(AfterReturnType) == error{}) return @field(HandlerType, after_name)(self, answer);
                        return try @field(HandlerType, after_name)(self, answer);
                    }
                },
                .direct_return => struct {
                    /// Convert one generated abort payload into the enclosing answer.
                    pub fn directReturn(self: HandlerPtrType, payload: OpPayloadType(op_type)) lowered_machine.ResetError(RunErrorSetType)!AnswerType {
                        const DirectReturnType = HandlerReturnType(HandlerType, op_type);
                        if (comptime OpPayloadType(op_type) == void) {
                            if (comptime ReturnTypeErrorSet(DirectReturnType) == error{}) return @field(HandlerType, opName(op_type))(self);
                            return try @field(HandlerType, opName(op_type))(self);
                        }
                        if (comptime ReturnTypeErrorSet(DirectReturnType) == error{}) return @field(HandlerType, opName(op_type))(self, payload);
                        return try @field(HandlerType, opName(op_type))(self, payload);
                    }
                },
            };
        }

        fn GeneratedSpecType(comptime AnswerType: type, comptime RunErrorSetType: type, comptime HandlerPtrType: type, comptime index: usize) type {
            const op_type = op_specs[index];
            const Impl = GeneratedImplType(AnswerType, RunErrorSetType, HandlerPtrType, index);
            return switch (mode) {
                .resume_then_transform => @TypeOf(internal.handleDirectTransform(op_type, dummyPointer(HandlerPtrType), Impl)),
                .resume_or_return => @TypeOf(internal.handleChoice(op_type, dummyPointer(HandlerPtrType), Impl)),
                .direct_return => @TypeOf(internal.handleAbort(op_type, dummyPointer(HandlerPtrType), Impl)),
            };
        }

        fn generatedSpec(
            comptime AnswerType: type,
            comptime RunErrorSetType: type,
            handler_ptr: anytype,
            comptime index: usize,
        ) GeneratedSpecType(AnswerType, RunErrorSetType, @TypeOf(handler_ptr), index) {
            const op_type = op_specs[index];
            const Impl = GeneratedImplType(AnswerType, RunErrorSetType, @TypeOf(handler_ptr), index);
            return switch (mode) {
                .resume_then_transform => internal.handleDirectTransform(op_type, handler_ptr, Impl),
                .resume_or_return => internal.handleChoice(op_type, handler_ptr, Impl),
                .direct_return => internal.handleAbort(op_type, handler_ptr, Impl),
            };
        }

        fn SpecsTupleType(comptime AnswerType: type, comptime RunErrorSetType: type, comptime HandlerPtrType: type) type {
            const HandlerType = std.meta.Child(HandlerPtrType);
            comptime assertHandlerBundle(mode, StateType, AnswerType, ErrorSetType, op_specs, HandlerType);
            return switch (op_specs.len) {
                1 => std.meta.Tuple(&.{GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 0)}),
                2 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 1) }),
                3 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 2) }),
                4 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 2), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 3) }),
                5 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 2), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 3), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 4) }),
                6 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 2), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 3), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 4), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 5) }),
                7 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 2), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 3), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 4), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 5), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 6) }),
                8 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 2), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 3), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 4), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 5), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 6), GeneratedSpecType(AnswerType, RunErrorSetType, HandlerPtrType, 7) }),
                else => unreachable,
            };
        }

        fn buildSpecs(comptime AnswerType: type, comptime RunErrorSetType: type, handler_ptr: anytype) SpecsTupleType(AnswerType, RunErrorSetType, @TypeOf(handler_ptr)) {
            return switch (op_specs.len) {
                1 => .{generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 0)},
                2 => .{ generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 0), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 1) },
                3 => .{ generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 0), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 1), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 2) },
                4 => .{ generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 0), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 1), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 2), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 3) },
                5 => .{ generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 0), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 1), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 2), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 3), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 4) },
                6 => .{ generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 0), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 1), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 2), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 3), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 4), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 5) },
                7 => .{ generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 0), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 1), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 2), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 3), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 4), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 5), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 6) },
                8 => .{ generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 0), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 1), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 2), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 3), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 4), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 5), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 6), generatedSpec(AnswerType, RunErrorSetType, handler_ptr, 7) },
                else => unreachable,
            };
        }

        fn HandleErrorSet(comptime AnswerType: type, comptime HandlerType: type, comptime Body: type) type {
            comptime assertHandlerBundle(mode, StateType, AnswerType, ErrorSetType, op_specs, HandlerType);
            const BaseErrorSet = ErrorSetType || InferHandlerErrorSet(mode, op_specs, HandlerType);
            return BaseErrorSet || PreviewBodyErrorSet(StateType, AnswerType, BaseErrorSet, mode, Body);
        }

        fn activeEngineContext(comptime Cap: type, ctx: anytype) *Cap.EngineContextType() {
            comptime family.assertContextType(Cap, @TypeOf(ctx));
            _ = ctx._cap;
            return @ptrCast(@alignCast(ctx._cap.engine_ctx.?));
        }

        fn LexicalFieldConfig(
            comptime Cap: type,
            comptime ContextPtrType: type,
            comptime HandlersType: type,
            comptime PreviousEffType: type,
            comptime index: usize,
        ) type {
            return struct {
                const Capability = Cap;
                const ContextPtr = ContextPtrType;
                const Handlers = HandlersType;
                const PreviousEff = PreviousEffType;
                const binder_index = index;
            };
        }

        fn LexicalOpFieldHandle(
            comptime tag: OpTag,
            comptime Config: type,
        ) type {
            const OpTypeValue = OpType(op_specs, tag);
            const RunErrorSetType = family.ContextErrorSetType(Config.ContextPtr);
            const CurrentDescriptorType = @typeInfo(Config.Handlers).@"struct".fields[Config.binder_index].type;
            const CurrentHandlerType = @FieldType(CurrentDescriptorType, "handler");
            const EffectiveErrorSet = RunErrorSetType || InferHandlerOperationErrorSet(mode, op_specs, CurrentHandlerType);
            return switch (mode) {
                .resume_then_transform => if (OpPayloadType(OpTypeValue) == void) struct {
                    ctx: ?Config.ContextPtr,

                    /// Perform one zero-payload generated lexical transform op.
                    pub fn perform(self: @This()) lowered_machine.ResetError(EffectiveErrorSet)!OpResumeType(OpTypeValue) {
                        return try Op(tag).perform(Config.Capability, self.ctx.?);
                    }
                } else struct {
                    ctx: ?Config.ContextPtr,

                    /// Perform one payload-carrying generated lexical transform op.
                    pub fn perform(self: @This(), payload: OpPayloadType(OpTypeValue)) lowered_machine.ResetError(EffectiveErrorSet)!OpResumeType(OpTypeValue) {
                        return try Op(tag).perform(Config.Capability, self.ctx.?, payload);
                    }
                },
                .resume_or_return => if (OpPayloadType(OpTypeValue) == void) struct {
                    const Handle = @This();
                    const ContinuationEff = lexical_with.ContinuationEffType(Config.Handlers, Config.binder_index, Config.PreviousEff, Handle);

                    ctx: ?Config.ContextPtr,
                    runtime: ?*shift.Runtime,
                    handlers_ptr: ?*Config.Handlers,
                    previous_eff: Config.PreviousEff,
                    outputs_ptr: ?*lexical_with.OutputBundleType(Config.Handlers),
                    caller_file: []const u8,
                    caller_line: u32,
                    caller_column: u32,

                    /// Perform one zero-payload generated lexical choice op.
                    pub fn perform(self: Handle, comptime Continuation: anytype) lowered_machine.ResetError(lexical_with.ChoiceExecutionErrorSet(EffectiveErrorSet, Continuation, OpResumeType(OpTypeValue), ContinuationEff))!lexical_with.ChoiceAnswerTypeFor(Continuation, OpResumeType(OpTypeValue), ContinuationEff) {
                        const request_state = struct {
                            /// Re-enter the lexical continuation after one generated choice resume.
                            pub fn apply(current_handle: *Handle, value: OpResumeType(OpTypeValue)) lowered_machine.ResetError(lexical_with.ChoiceExecutionErrorSet(EffectiveErrorSet, Continuation, OpResumeType(OpTypeValue), ContinuationEff))!lexical_with.ChoiceAnswerTypeFor(Continuation, OpResumeType(OpTypeValue), ContinuationEff) {
                                return try lexical_with.continueChoice(
                                    Config.Handlers,
                                    Config.binder_index,
                                    .{
                                        .runtime = current_handle.runtime.?,
                                        .handlers_ptr = current_handle.handlers_ptr.?,
                                        .previous_eff = current_handle.previous_eff,
                                        .current_handle = current_handle.*,
                                        .outputs_ptr = current_handle.outputs_ptr.?,
                                        .caller_file = current_handle.caller_file,
                                        .caller_line = current_handle.caller_line,
                                        .caller_column = current_handle.caller_column,
                                    },
                                    Continuation,
                                    value,
                                );
                            }
                        };

                        var current_handle = self;
                        var authored = activeEngineContext(Config.Capability, self.ctx.?).performProgramWithContext(OpTypeValue, {}, &current_handle, request_state);
                        if (@hasDecl(@TypeOf(authored), "has_compiled_plan") and @TypeOf(authored).has_compiled_plan) {
                            return try authored.runCompiled(self.runtime.?);
                        }
                        authored.activate();
                        defer authored.deactivate();
                        return try frontend.run(self.runtime.?, authored.prompt, authored.program);
                    }
                } else struct {
                    const Handle = @This();
                    const ContinuationEff = lexical_with.ContinuationEffType(Config.Handlers, Config.binder_index, Config.PreviousEff, Handle);

                    ctx: ?Config.ContextPtr,
                    runtime: ?*shift.Runtime,
                    handlers_ptr: ?*Config.Handlers,
                    previous_eff: Config.PreviousEff,
                    outputs_ptr: ?*lexical_with.OutputBundleType(Config.Handlers),
                    caller_file: []const u8,
                    caller_line: u32,
                    caller_column: u32,

                    /// Perform one payload-carrying generated lexical choice op.
                    pub fn perform(self: Handle, payload: OpPayloadType(OpTypeValue), comptime Continuation: anytype) lowered_machine.ResetError(lexical_with.ChoiceExecutionErrorSet(EffectiveErrorSet, Continuation, OpResumeType(OpTypeValue), ContinuationEff))!lexical_with.ChoiceAnswerTypeFor(Continuation, OpResumeType(OpTypeValue), ContinuationEff) {
                        const request_state = struct {
                            /// Re-enter the lexical continuation after one generated choice resume.
                            pub fn apply(current_handle: *Handle, value: OpResumeType(OpTypeValue)) lowered_machine.ResetError(lexical_with.ChoiceExecutionErrorSet(EffectiveErrorSet, Continuation, OpResumeType(OpTypeValue), ContinuationEff))!lexical_with.ChoiceAnswerTypeFor(Continuation, OpResumeType(OpTypeValue), ContinuationEff) {
                                return try lexical_with.continueChoice(
                                    Config.Handlers,
                                    Config.binder_index,
                                    .{
                                        .runtime = current_handle.runtime.?,
                                        .handlers_ptr = current_handle.handlers_ptr.?,
                                        .previous_eff = current_handle.previous_eff,
                                        .current_handle = current_handle.*,
                                        .outputs_ptr = current_handle.outputs_ptr.?,
                                        .caller_file = current_handle.caller_file,
                                        .caller_line = current_handle.caller_line,
                                        .caller_column = current_handle.caller_column,
                                    },
                                    Continuation,
                                    value,
                                );
                            }
                        };

                        var current_handle = self;
                        var authored = activeEngineContext(Config.Capability, self.ctx.?).performProgramWithContext(OpTypeValue, payload, &current_handle, request_state);
                        if (@hasDecl(@TypeOf(authored), "has_compiled_plan") and @TypeOf(authored).has_compiled_plan) {
                            return try authored.runCompiled(self.runtime.?);
                        }
                        authored.activate();
                        defer authored.deactivate();
                        return try frontend.run(self.runtime.?, authored.prompt, authored.program);
                    }
                },
                .direct_return => if (OpPayloadType(OpTypeValue) == void) struct {
                    ctx: ?Config.ContextPtr,

                    /// Perform one zero-payload generated lexical abort op.
                    pub fn abort(self: @This()) lowered_machine.ResetError(EffectiveErrorSet)!noreturn {
                        return try Op(tag).perform(Config.Capability, self.ctx.?);
                    }
                } else struct {
                    ctx: ?Config.ContextPtr,

                    /// Perform one payload-carrying generated lexical abort op.
                    pub fn abort(self: @This(), payload: OpPayloadType(OpTypeValue)) lowered_machine.ResetError(EffectiveErrorSet)!noreturn {
                        return try Op(tag).perform(Config.Capability, self.ctx.?, payload);
                    }
                },
            };
        }

        fn LexicalFieldContainerHandle(
            comptime Cap: type,
            comptime ContextPtrType: type,
            comptime HandlersType: type,
            comptime PreviousEffType: type,
            comptime index: usize,
        ) type {
            var fields = [_]std.builtin.Type.StructField{.{
                .name = "",
                .type = void,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(void),
            }} ** op_specs.len;

            inline for (op_specs, 0..) |SpecOp, field_index| {
                const tag = @field(OpTag, opName(SpecOp));
                const FieldType = LexicalOpFieldHandle(tag, LexicalFieldConfig(Cap, ContextPtrType, HandlersType, PreviousEffType, index));
                fields[field_index] = .{
                    .name = opName(SpecOp),
                    .type = FieldType,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(FieldType),
                };
            }

            return @Type(.{
                .@"struct" = .{
                    .layout = .auto,
                    .fields = &fields,
                    .decls = &.{},
                    .is_tuple = false,
                },
            });
        }

        /// Lexical handle used by `shift.with(...)` for generated families.
        pub fn LexicalHandle(
            comptime Cap: type,
            comptime ContextPtrType: type,
            comptime HandlersType: type,
            comptime PreviousEffType: type,
            comptime index: usize,
        ) type {
            return LexicalFieldContainerHandle(Cap, ContextPtrType, HandlersType, PreviousEffType, index);
        }

        /// Descriptor value used by `shift.with(...)` for generated families.
        pub fn LexicalDescriptor(comptime HandlerType: type) type {
            return struct {
                const produces_output = mode == .resume_then_transform and stateTypeProducesOutput(StateType);

                /// Shared error set carried by the generated lexical descriptor.
                pub const ErrorSet = ErrorSetType;
                /// State type threaded through the generated lexical context.
                pub const State = StateType;
                /// Final generated descriptor output; transform families emit final state and control families emit no extra output.
                pub const Output = if (produces_output) StateType else void;

                handler: HandlerType,

                /// Resolve the generated lexical handle type for one exact context.
                pub fn HandleType(
                    comptime Cap: type,
                    comptime ContextPtrType: type,
                    comptime HandlersType: type,
                    comptime PreviousEffType: type,
                    comptime index: usize,
                ) type {
                    return LexicalHandle(Cap, ContextPtrType, HandlersType, PreviousEffType, index);
                }

                /// Bind one generated lexical handle bundle to the active exact context and private binder frame.
                pub fn bindLexical(
                    self: @This(),
                    comptime Cap: type,
                    ctx: anytype,
                    comptime HandlersType: type,
                    comptime PreviousEffType: type,
                    comptime index: usize,
                ) HandleType(Cap, @TypeOf(ctx), HandlersType, PreviousEffType, index) {
                    _ = self;
                    const lexical_state = lexical_with.activeLexicalState(ctx, HandlersType, PreviousEffType);
                    var field_container = std.mem.zeroInit(HandleType(Cap, @TypeOf(ctx), HandlersType, PreviousEffType, index), .{});
                    inline for (op_specs) |SpecOp| {
                        const field_handle = switch (mode) {
                            .resume_then_transform => LexicalOpFieldHandle(@field(OpTag, opName(SpecOp)), LexicalFieldConfig(Cap, @TypeOf(ctx), HandlersType, PreviousEffType, index)){
                                .ctx = ctx,
                            },
                            .resume_or_return => LexicalOpFieldHandle(@field(OpTag, opName(SpecOp)), LexicalFieldConfig(Cap, @TypeOf(ctx), HandlersType, PreviousEffType, index)){
                                .ctx = ctx,
                                .runtime = lexical_state.runtime,
                                .handlers_ptr = lexical_state.handlers_ptr,
                                .previous_eff = lexical_state.eff_value,
                                .outputs_ptr = lexical_state.outputs_ptr,
                                .caller_file = lexical_state.caller_file,
                                .caller_line = lexical_state.caller_line,
                                .caller_column = lexical_state.caller_column,
                            },
                            .direct_return => LexicalOpFieldHandle(@field(OpTag, opName(SpecOp)), LexicalFieldConfig(Cap, @TypeOf(ctx), HandlersType, PreviousEffType, index)){
                                .ctx = ctx,
                            },
                        };
                        @field(field_container, opName(SpecOp)) = field_handle;
                    }
                    return field_container;
                }

                /// Return the shared binding schema for this lexical descriptor under one requirement label.
                pub fn BindingSchema(comptime requirement_label: [:0]const u8) type {
                    return effect_schema.Binding(requirement_label, self_type.Schema(), HandlerType);
                }

                /// Run one generated lexical descriptor through the existing generated-family handler path.
                pub fn run(self: @This(), comptime AnswerType: type, comptime RunErrorSetType: type, run_ctx: anytype, comptime Body: type) lowered_machine.ResetError(RunErrorSetType || InferHandlerOperationErrorSet(mode, op_specs, HandlerType))!lexical_with.DescriptorResult(Output, AnswerType) {
                    var instance = Instance.init();
                    const ActualRunErrorSet = RunErrorSetType || InferHandlerOperationErrorSet(mode, op_specs, HandlerType);
                    const result = try self_type.handleWithLexicalState(AnswerType, ActualRunErrorSet, run_ctx.runtime, &instance, self.handler, @constCast(run_ctx.lexical_state), Body, @TypeOf(run_ctx).caller_source);
                    if (produces_output) {
                        return .{
                            .output = result.state,
                            .value = result.value,
                        };
                    }
                    if (mode == .resume_then_transform) {
                        return .{
                            .output = {},
                            .value = result.value,
                        };
                    }
                    return .{
                        .output = {},
                        .value = result,
                    };
                }
            };
        }

        /// Create one lexical descriptor for a generated family.
        pub fn use(config: anytype) LexicalDescriptor(@TypeOf(config.handler)) {
            return .{ .handler = config.handler };
        }

        /// Run one generated family body under a fresh exact context and hidden engine bindings.
        pub fn handle(comptime AnswerType: type, runtime: *shift.Runtime, instance: anytype, handler: anytype, comptime Body: type) lowered_machine.ResetError(HandleErrorSet(AnswerType, @TypeOf(handler), Body))!if (mode == .resume_then_transform) HandleResult(AnswerType) else AnswerType {
            const HandlerType = @TypeOf(handler);
            const RunErrorSetType = HandleErrorSet(AnswerType, HandlerType, Body);
            return self_type.handleWithErrorSet(AnswerType, RunErrorSetType, runtime, instance, handler, Body);
        }

        /// Public `handleWithErrorSet` helper.
        pub fn handleWithErrorSet(comptime AnswerType: type, comptime RunErrorSetType: type, runtime: *shift.Runtime, instance: anytype, handler: anytype, comptime Body: type) lowered_machine.ResetError(RunErrorSetType)!if (mode == .resume_then_transform) HandleResult(AnswerType) else AnswerType {
            return self_type.handleWithLexicalState(AnswerType, RunErrorSetType, runtime, instance, handler, null, Body, null);
        }

        // zlinter-disable max_positional_args - this internal seam keeps the lexical caller packet explicit until compiled-body dispatch fully replaces the legacy path.
        fn handleWithLexicalState(comptime AnswerType: type, comptime RunErrorSetType: type, runtime: *shift.Runtime, instance: anytype, handler: anytype, lexical_state: ?*anyopaque, comptime Body: type, comptime caller_source: ?std.builtin.SourceLocation) lowered_machine.ResetError(RunErrorSetType)!if (mode == .resume_then_transform) HandleResult(AnswerType) else AnswerType {
            var handler_value = handler;
            const handler_ptr = &handler_value;
            const HandlerType = @TypeOf(handler_value);
            comptime assertHandlerBundle(mode, StateType, AnswerType, ErrorSetType, op_specs, HandlerType);

            const specs = buildSpecs(AnswerType, RunErrorSetType, handler_ptr);
            const Configured = @TypeOf(internal.Program(AnswerType, AnswerType, RunErrorSetType, op_specs).handlers(specs));
            const BindingsType = internal.BindingChainFor(@TypeOf(specs), AnswerType, AnswerType, RunErrorSetType);
            var bindings = BindingsType.initWithPrompt(specs, &instance.prompt);
            var engine_ctx = Configured.Context{ .bindings = &bindings };

            const capability_meta = struct {
                const body_tag = Body;

                /// Return the engine context type for this public helper.
                pub fn EngineContextType() type {
                    return Configured.Context;
                }
            };

            const sealed_contract = struct {
                const PromptTypeG = prompt_contract.Prompt(mode, AnswerType, AnswerType, RunErrorSetType);
                const StateTypeG = StateType;
                const AnswerTypeG = AnswerType;
                const ErrorSetTypeG = RunErrorSetType;
                const capability_decls = capability_meta;
            };
            const value = try sealed_engine.runWithSealedEngine(
                sealed_contract.PromptTypeG,
                sealed_contract.StateTypeG,
                sealed_contract.AnswerTypeG,
                sealed_contract.ErrorSetTypeG,
                sealed_contract.capability_decls,
                .{ .runtime = runtime, .prompt_identity = promptIdentity(&instance.prompt), .engine_ctx = &engine_ctx, .lexical_state = lexical_state, .caller_source = caller_source },
                Body,
            );
            if (mode == .resume_then_transform) {
                return .{
                    .state = if (@hasField(HandlerType, "state")) handler_value.state else defaultStatelessStateValue(StateType),
                    .value = value,
                };
            }
            return value;
        }

        /// Resolve one generated op namespace by tag.
        pub fn Op(comptime tag: OpTag) type {
            const OpTypeValue = OpType(op_specs, tag);
            if (mode == .resume_then_transform and OpTypeValue.Payload == void) return struct {
                /// Payload type carried by this generated op.
                pub const Payload = OpTypeValue.Payload;
                /// Resume type produced by this generated op.
                pub const Resume = OpTypeValue.Resume;
                /// Prompt mode carried by this generated op.
                pub const op_mode = OpTypeValue.mode;

                /// Perform one zero-payload generated transform op through the active exact context.
                pub fn perform(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!OpTypeValue.Resume {
                    comptime family.assertContextType(Cap, @TypeOf(ctx));
                    return try activeEngineContext(Cap, ctx).perform(OpTypeValue, {});
                }
            };
            if (mode == .resume_then_transform) return struct {
                /// Payload type carried by this generated op.
                pub const Payload = OpTypeValue.Payload;
                /// Resume type produced by this generated op.
                pub const Resume = OpTypeValue.Resume;
                /// Prompt mode carried by this generated op.
                pub const op_mode = OpTypeValue.mode;

                /// Perform one payload-carrying generated transform op through the active exact context.
                pub fn perform(comptime Cap: type, ctx: anytype, payload: OpTypeValue.Payload) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!OpTypeValue.Resume {
                    comptime family.assertContextType(Cap, @TypeOf(ctx));
                    return try activeEngineContext(Cap, ctx).perform(OpTypeValue, payload);
                }
            };
            if (OpTypeValue.Payload == void) return struct {
                /// Payload type carried by this generated op.
                pub const Payload = OpTypeValue.Payload;
                /// Resume type produced by this generated op.
                pub const Resume = OpTypeValue.Resume;
                /// Prompt mode carried by this generated op.
                pub const op_mode = OpTypeValue.mode;

                /// Perform one zero-payload generated control op through the active exact context.
                pub fn perform(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!OpTypeValue.Resume {
                    comptime family.assertContextType(Cap, @TypeOf(ctx));
                    return try activeEngineContext(Cap, ctx).perform(OpTypeValue, {});
                }

                /// Build one explicit zero-payload generated control op program.
                pub fn program(comptime Cap: type, ctx: anytype, comptime Continuation: anytype) @TypeOf(activeEngineContext(Cap, ctx).performProgram(OpTypeValue, {}, Continuation)) {
                    comptime family.assertContextType(Cap, @TypeOf(ctx));
                    return activeEngineContext(Cap, ctx).performProgram(OpTypeValue, {}, Continuation);
                }
            };
            return struct {
                /// Payload type carried by this generated op.
                pub const Payload = OpTypeValue.Payload;
                /// Resume type produced by this generated op.
                pub const Resume = OpTypeValue.Resume;
                /// Prompt mode carried by this generated op.
                pub const op_mode = OpTypeValue.mode;

                /// Perform one payload-carrying generated control op through the active exact context.
                pub fn perform(comptime Cap: type, ctx: anytype, payload: OpTypeValue.Payload) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!OpTypeValue.Resume {
                    comptime family.assertContextType(Cap, @TypeOf(ctx));
                    return try activeEngineContext(Cap, ctx).perform(OpTypeValue, payload);
                }

                /// Build one explicit payload-carrying generated control op program.
                pub fn program(comptime Cap: type, ctx: anytype, payload: OpTypeValue.Payload, comptime Continuation: anytype) @TypeOf(activeEngineContext(Cap, ctx).performProgram(OpTypeValue, payload, Continuation)) {
                    comptime family.assertContextType(Cap, @TypeOf(ctx));
                    return activeEngineContext(Cap, ctx).performProgram(OpTypeValue, payload, Continuation);
                }
            };
        }

        /// Public proof-helper surface for generated families.
        pub const proof = struct {
            /// Expected compile-fail marker for missing-context misuse.
            pub const expected_missing_context = "expected a pointer to a shift.effect context";
            /// Expected compile-fail marker for forged-context misuse.
            pub const expected_forged_context = "expected exact shift.effect context type";
            /// Expected compile-fail marker for cross-instance misuse.
            pub const expected_cross_instance = "context capability does not match supplied capability";

            /// Run one generated-family example harness through the public handle surface.
            pub fn exampleHarness(comptime AnswerType: type, runtime: *shift.Runtime, instance: anytype, handler: anytype, comptime Body: type) lowered_machine.ResetError(HandleErrorSet(AnswerType, @TypeOf(handler), Body))!if (mode == .resume_then_transform) HandleResult(AnswerType) else AnswerType {
                return self_type.handle(AnswerType, runtime, instance, handler, Body);
            }
        };
    };
}
