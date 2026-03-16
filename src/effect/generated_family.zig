const choice = @import("choice.zig");
const family = @import("family.zig");
const frontend = @import("../frontend.zig");
const internal = @import("../internal/algebraic_engine.zig");
const lexical_with = @import("../with_api.zig");
const prompt_contract = @import("../prompt_contract.zig");
const shift = @import("../root.zig");
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

fn assertSpecShape(comptime SpecType: type) void {
    if (!@hasField(SpecType, "state_type")) @compileError("generated effect spec must declare state_type");
    if (!@hasField(SpecType, "error_set_type")) @compileError("generated effect spec must declare error_set_type");
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
    const Child = std.meta.Child(PtrType);
    const addr = comptime std.mem.alignForward(usize, 1, @alignOf(Child));
    return @as(PtrType, @ptrFromInt(addr));
}

fn assertTransformHandlerBundle(comptime HandlerType: type, comptime StateType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime Op: type) void {
    if (!@hasField(HandlerType, "state")) @compileError("generated transform handler must declare state");
    if (@FieldType(HandlerType, "state") != StateType) @compileError("generated transform handler state field must match state_type");
    if (!@hasDecl(HandlerType, opName(Op))) @compileError("generated transform handler is missing op method");

    const ResumeFn = @TypeOf(@field(HandlerType, opName(Op)));
    if (comptime OpPayloadType(Op) == void) {
        if (ResumeFn != fn (*HandlerType) OpResumeType(Op) and ResumeFn != fn (*HandlerType) shift.ResetError(ErrorSetType)!OpResumeType(Op)) {
            @compileError("generated transform handler op method must have type fn (*Handler) Resume or fn (*Handler) ResetError(ErrorSet)!Resume");
        }
    } else {
        if (ResumeFn != fn (*HandlerType, OpPayloadType(Op)) OpResumeType(Op) and ResumeFn != fn (*HandlerType, OpPayloadType(Op)) shift.ResetError(ErrorSetType)!OpResumeType(Op)) {
            @compileError("generated transform handler op method must have type fn (*Handler, Payload) Resume or fn (*Handler, Payload) ResetError(ErrorSet)!Resume");
        }
    }

    const after_name = comptime afterMethodName(opName(Op));
    if (!@hasDecl(HandlerType, after_name)) @compileError("generated transform handler is missing after_<op> method");
    const AfterFn = @TypeOf(@field(HandlerType, after_name));
    if (AfterFn != fn (*HandlerType, AnswerType) AnswerType and AfterFn != fn (*HandlerType, AnswerType) shift.ResetError(ErrorSetType)!AnswerType) {
        @compileError("generated transform handler after_<op> must have type fn (*Handler, Answer) Answer or fn (*Handler, Answer) ResetError(ErrorSet)!Answer");
    }
}

fn assertChoiceHandlerBundle(comptime HandlerType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime Op: type) void {
    if (!@hasDecl(HandlerType, opName(Op))) @compileError("generated choice handler is missing op method");
    const DecisionType = choice.Decision(OpResumeType(Op), AnswerType);
    const ResumeFn = @TypeOf(@field(HandlerType, opName(Op)));
    if (comptime OpPayloadType(Op) == void) {
        if (ResumeFn != fn (*HandlerType) DecisionType and ResumeFn != fn (*HandlerType) shift.ResetError(ErrorSetType)!DecisionType) {
            @compileError("generated choice handler op method must have type fn (*Handler) effect.choice.Decision or fn (*Handler) ResetError(ErrorSet)!effect.choice.Decision");
        }
    } else {
        if (ResumeFn != fn (*HandlerType, OpPayloadType(Op)) DecisionType and ResumeFn != fn (*HandlerType, OpPayloadType(Op)) shift.ResetError(ErrorSetType)!DecisionType) {
            @compileError("generated choice handler op method must have type fn (*Handler, Payload) effect.choice.Decision or fn (*Handler, Payload) ResetError(ErrorSet)!effect.choice.Decision");
        }
    }

    const after_name = comptime afterMethodName(opName(Op));
    if (!@hasDecl(HandlerType, after_name)) @compileError("generated choice handler is missing after_<op> method");
    const AfterFn = @TypeOf(@field(HandlerType, after_name));
    if (AfterFn != fn (*HandlerType, AnswerType) AnswerType and AfterFn != fn (*HandlerType, AnswerType) shift.ResetError(ErrorSetType)!AnswerType) {
        @compileError("generated choice handler after_<op> must have type fn (*Handler, Answer) Answer or fn (*Handler, Answer) ResetError(ErrorSet)!Answer");
    }
}

fn assertAbortHandlerBundle(comptime HandlerType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime Op: type) void {
    if (!@hasDecl(HandlerType, opName(Op))) @compileError("generated abort handler is missing op method");
    const DirectFn = @TypeOf(@field(HandlerType, opName(Op)));
    if (comptime OpPayloadType(Op) == void) {
        if (DirectFn != fn (*HandlerType) AnswerType and DirectFn != fn (*HandlerType) shift.ResetError(ErrorSetType)!AnswerType) {
            @compileError("generated abort handler op method must have type fn (*Handler) Answer or fn (*Handler) ResetError(ErrorSet)!Answer");
        }
    } else {
        if (DirectFn != fn (*HandlerType, OpPayloadType(Op)) AnswerType and DirectFn != fn (*HandlerType, OpPayloadType(Op)) shift.ResetError(ErrorSetType)!AnswerType) {
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

fn computeProgramForPrompt(
    comptime Cap: type,
    ctx: anytype,
    comptime PromptType: type,
    thunk: anytype,
) frontend.Program(PromptType) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const shim = family.ProgramShimFor(ContextType);
    const ThunkType = @TypeOf(thunk);
    _ = ctx._cap;
    return frontend.computeProgram(PromptType, struct {
        fn invoke() shift.ResetError(ContextType.ErrorSetType)!ContextType.AnswerType {
            switch (@typeInfo(ThunkType)) {
                .@"fn" => {
                    const params = @typeInfo(ThunkType).@"fn".params;
                    const ReturnType = @typeInfo(ThunkType).@"fn".return_type.?;
                    if (params.len == 0) {
                        if (@typeInfo(ReturnType) != .error_union) return thunk();
                        return try thunk();
                    }
                    if (@typeInfo(ReturnType) != .error_union) return thunk(Cap, shim.active_context.?);
                    return try thunk(Cap, shim.active_context.?);
                },
                .pointer => |pointer| {
                    if (@typeInfo(pointer.child) == .@"fn") {
                        const params = @typeInfo(pointer.child).@"fn".params;
                        const ReturnType = @typeInfo(pointer.child).@"fn".return_type.?;
                        if (params.len == 0) {
                            if (@typeInfo(ReturnType) != .error_union) return thunk();
                            return try thunk();
                        }
                        if (@typeInfo(ReturnType) != .error_union) return thunk(Cap, shim.active_context.?);
                        return try thunk(Cap, shim.active_context.?);
                    }
                },
                else => {},
            }

            const RunFn = @TypeOf(thunk.run);
            const params = @typeInfo(RunFn).@"fn".params;
            const ReturnType = @typeInfo(RunFn).@"fn".return_type.?;
            if (params.len == 0) {
                if (@typeInfo(ReturnType) != .error_union) return thunk.run();
                return try thunk.run();
            }
            if (@typeInfo(ReturnType) != .error_union) return thunk.run(Cap, shim.active_context.?);
            return try thunk.run(Cap, shim.active_context.?);
        }
    }.invoke);
}

fn runWithSealedEngine(comptime Contract: type, config: anytype, comptime Body: type) shift.ResetError(Contract.ErrorSetTypeG)!Contract.AnswerTypeG {
    const PromptType = Contract.PromptTypeG;
    const StateType = Contract.StateTypeG;
    const AnswerType = Contract.AnswerTypeG;
    const ErrorSetType = Contract.ErrorSetTypeG;
    const capability_decls = Contract.capability_decls;
    const EnginePtrType = @TypeOf(config.engine_ctx);
    const EngineContextType = switch (@typeInfo(EnginePtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected engine context pointer"),
    };

    const runner = struct {
        threadlocal var active_runtime: ?*shift.Runtime = null;
        threadlocal var active_prompt_token: prompt_contract.PromptToken = 0;
        threadlocal var active_engine_ctx: ?*EngineContextType = null;

        /// Execute one generated-family body under the installed exact context and engine bindings.
        pub fn run(comptime Cap: type, ctx: anytype) shift.ResetError(ErrorSetType)!AnswerType {
            const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
            const context_shim = family.ProgramShimFor(ContextType);
            const engine_shim = family.EngineShim(ContextType, EngineContextType);
            var prompt = PromptType{ .token = active_prompt_token };

            const previous_context = context_shim.active_context;
            const previous_engine = engine_shim.active_engine;
            context_shim.active_context = ctx;
            engine_shim.active_engine = active_engine_ctx;
            defer {
                context_shim.active_context = previous_context;
                engine_shim.active_engine = previous_engine;
            }

            if (comptime family.hasDeclSafe(Body, "program")) {
                const AuthoredType = @TypeOf(Body.program(Cap, ctx));
                if (@typeInfo(AuthoredType) == .@"struct") {
                    const authored = Body.program(Cap, ctx);
                    authored.activate();
                    defer authored.deactivate();
                    return try frontend.run(active_runtime.?, authored.prompt, authored.program);
                }
                return try frontend.run(active_runtime.?, &prompt, Body.program(Cap, ctx));
            }
            if (comptime family.hasDeclSafe(Body, "body")) {
                return try frontend.run(active_runtime.?, &prompt, computeProgramForPrompt(Cap, ctx, PromptType, Body.body));
            }
            @compileError("generated effect body must declare program or body");
        }
    };

    const previous_runtime = runner.active_runtime;
    const previous_prompt_token = runner.active_prompt_token;
    const previous_engine_ctx = runner.active_engine_ctx;
    runner.active_runtime = config.runtime;
    runner.active_prompt_token = config.prompt_token;
    runner.active_engine_ctx = config.engine_ctx;
    defer runner.active_runtime = previous_runtime;
    defer runner.active_prompt_token = previous_prompt_token;
    defer runner.active_engine_ctx = previous_engine_ctx;

    return try family.withCapability(family.ContextSpec(StateType, AnswerType, ErrorSetType), capability_decls, AnswerType, runner);
}

/// Build one sealed generated effect family from a declarative comptime spec.
pub fn Build(comptime spec: anytype) type {
    const SpecType = @TypeOf(spec);
    comptime @setEvalBranchQuota(20_000);
    comptime assertSpecShape(SpecType);
    const StateType: type = spec.state_type;
    const ErrorSetType: type = spec.error_set_type;
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
            return computeProgramForPrompt(Cap, ctx, FamilyPrompt, thunk);
        }

        fn GeneratedImplType(comptime AnswerType: type, comptime HandlerPtrType: type, comptime index: usize) type {
            const HandlerType = std.meta.Child(HandlerPtrType);
            const op_type = op_specs[index];
            return switch (mode) {
                .resume_then_transform => struct {
                    /// Produce one resumptive value from the generated handler bundle.
                    pub fn resumeValue(self: HandlerPtrType, payload: OpPayloadType(op_type)) shift.ResetError(ErrorSetType)!OpResumeType(op_type) {
                        const ResumeFn = @TypeOf(@field(HandlerType, opName(op_type)));
                        if (comptime OpPayloadType(op_type) == void) {
                            if (ResumeFn == fn (HandlerPtrType) OpResumeType(op_type)) return @field(HandlerType, opName(op_type))(self);
                            return try @field(HandlerType, opName(op_type))(self);
                        }
                        if (ResumeFn == fn (HandlerPtrType, OpPayloadType(op_type)) OpResumeType(op_type)) return @field(HandlerType, opName(op_type))(self, payload);
                        return try @field(HandlerType, opName(op_type))(self, payload);
                    }

                    /// Convert one resumed answer into the enclosing generated answer.
                    pub fn afterResume(self: HandlerPtrType, answer: AnswerType) shift.ResetError(ErrorSetType)!AnswerType {
                        const after_name = comptime afterMethodName(opName(op_type));
                        const AfterFn = @TypeOf(@field(HandlerType, after_name));
                        if (AfterFn == fn (HandlerPtrType, AnswerType) AnswerType) return @field(HandlerType, after_name)(self, answer);
                        return try @field(HandlerType, after_name)(self, answer);
                    }
                },
                .resume_or_return => struct {
                    /// Decide whether one generated choice op resumes or returns now.
                    pub fn resumeOrReturn(self: HandlerPtrType, payload: OpPayloadType(op_type)) shift.ResetError(ErrorSetType)!choice.Decision(OpResumeType(op_type), AnswerType) {
                        const ResumeFn = @TypeOf(@field(HandlerType, opName(op_type)));
                        if (comptime OpPayloadType(op_type) == void) {
                            if (ResumeFn == fn (HandlerPtrType) choice.Decision(OpResumeType(op_type), AnswerType)) return @field(HandlerType, opName(op_type))(self);
                            return try @field(HandlerType, opName(op_type))(self);
                        }
                        if (ResumeFn == fn (HandlerPtrType, OpPayloadType(op_type)) choice.Decision(OpResumeType(op_type), AnswerType)) return @field(HandlerType, opName(op_type))(self, payload);
                        return try @field(HandlerType, opName(op_type))(self, payload);
                    }

                    /// Convert one resumed choice answer into the enclosing generated answer.
                    pub fn afterResume(self: HandlerPtrType, answer: AnswerType) shift.ResetError(ErrorSetType)!AnswerType {
                        const after_name = comptime afterMethodName(opName(op_type));
                        const AfterFn = @TypeOf(@field(HandlerType, after_name));
                        if (AfterFn == fn (HandlerPtrType, AnswerType) AnswerType) return @field(HandlerType, after_name)(self, answer);
                        return try @field(HandlerType, after_name)(self, answer);
                    }
                },
                .direct_return => struct {
                    /// Convert one generated abort payload into the enclosing answer.
                    pub fn directReturn(self: HandlerPtrType, payload: OpPayloadType(op_type)) shift.ResetError(ErrorSetType)!AnswerType {
                        const DirectFn = @TypeOf(@field(HandlerType, opName(op_type)));
                        if (comptime OpPayloadType(op_type) == void) {
                            if (DirectFn == fn (HandlerPtrType) AnswerType) return @field(HandlerType, opName(op_type))(self);
                            return try @field(HandlerType, opName(op_type))(self);
                        }
                        if (DirectFn == fn (HandlerPtrType, OpPayloadType(op_type)) AnswerType) return @field(HandlerType, opName(op_type))(self, payload);
                        return try @field(HandlerType, opName(op_type))(self, payload);
                    }
                },
            };
        }

        fn GeneratedSpecType(comptime AnswerType: type, comptime HandlerPtrType: type, comptime index: usize) type {
            const op_type = op_specs[index];
            const Impl = GeneratedImplType(AnswerType, HandlerPtrType, index);
            return switch (mode) {
                .resume_then_transform => @TypeOf(internal.handleDirectTransform(op_type, dummyPointer(HandlerPtrType), Impl)),
                .resume_or_return => @TypeOf(internal.handleChoice(op_type, dummyPointer(HandlerPtrType), Impl)),
                .direct_return => @TypeOf(internal.handleAbort(op_type, dummyPointer(HandlerPtrType), Impl)),
            };
        }

        fn generatedSpec(
            comptime AnswerType: type,
            handler_ptr: anytype,
            comptime index: usize,
        ) GeneratedSpecType(AnswerType, @TypeOf(handler_ptr), index) {
            const op_type = op_specs[index];
            const Impl = GeneratedImplType(AnswerType, @TypeOf(handler_ptr), index);
            return switch (mode) {
                .resume_then_transform => internal.handleDirectTransform(op_type, handler_ptr, Impl),
                .resume_or_return => internal.handleChoice(op_type, handler_ptr, Impl),
                .direct_return => internal.handleAbort(op_type, handler_ptr, Impl),
            };
        }

        fn SpecsTupleType(comptime AnswerType: type, comptime HandlerPtrType: type) type {
            const HandlerType = std.meta.Child(HandlerPtrType);
            comptime assertHandlerBundle(mode, StateType, AnswerType, ErrorSetType, op_specs, HandlerType);
            return switch (op_specs.len) {
                1 => std.meta.Tuple(&.{GeneratedSpecType(AnswerType, HandlerPtrType, 0)}),
                2 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, HandlerPtrType, 1) }),
                3 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, HandlerPtrType, 2) }),
                4 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, HandlerPtrType, 2), GeneratedSpecType(AnswerType, HandlerPtrType, 3) }),
                5 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, HandlerPtrType, 2), GeneratedSpecType(AnswerType, HandlerPtrType, 3), GeneratedSpecType(AnswerType, HandlerPtrType, 4) }),
                6 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, HandlerPtrType, 2), GeneratedSpecType(AnswerType, HandlerPtrType, 3), GeneratedSpecType(AnswerType, HandlerPtrType, 4), GeneratedSpecType(AnswerType, HandlerPtrType, 5) }),
                7 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, HandlerPtrType, 2), GeneratedSpecType(AnswerType, HandlerPtrType, 3), GeneratedSpecType(AnswerType, HandlerPtrType, 4), GeneratedSpecType(AnswerType, HandlerPtrType, 5), GeneratedSpecType(AnswerType, HandlerPtrType, 6) }),
                8 => std.meta.Tuple(&.{ GeneratedSpecType(AnswerType, HandlerPtrType, 0), GeneratedSpecType(AnswerType, HandlerPtrType, 1), GeneratedSpecType(AnswerType, HandlerPtrType, 2), GeneratedSpecType(AnswerType, HandlerPtrType, 3), GeneratedSpecType(AnswerType, HandlerPtrType, 4), GeneratedSpecType(AnswerType, HandlerPtrType, 5), GeneratedSpecType(AnswerType, HandlerPtrType, 6), GeneratedSpecType(AnswerType, HandlerPtrType, 7) }),
                else => unreachable,
            };
        }

        fn buildSpecs(comptime AnswerType: type, handler_ptr: anytype) SpecsTupleType(AnswerType, @TypeOf(handler_ptr)) {
            return switch (op_specs.len) {
                1 => .{generatedSpec(AnswerType, handler_ptr, 0)},
                2 => .{ generatedSpec(AnswerType, handler_ptr, 0), generatedSpec(AnswerType, handler_ptr, 1) },
                3 => .{ generatedSpec(AnswerType, handler_ptr, 0), generatedSpec(AnswerType, handler_ptr, 1), generatedSpec(AnswerType, handler_ptr, 2) },
                4 => .{ generatedSpec(AnswerType, handler_ptr, 0), generatedSpec(AnswerType, handler_ptr, 1), generatedSpec(AnswerType, handler_ptr, 2), generatedSpec(AnswerType, handler_ptr, 3) },
                5 => .{ generatedSpec(AnswerType, handler_ptr, 0), generatedSpec(AnswerType, handler_ptr, 1), generatedSpec(AnswerType, handler_ptr, 2), generatedSpec(AnswerType, handler_ptr, 3), generatedSpec(AnswerType, handler_ptr, 4) },
                6 => .{ generatedSpec(AnswerType, handler_ptr, 0), generatedSpec(AnswerType, handler_ptr, 1), generatedSpec(AnswerType, handler_ptr, 2), generatedSpec(AnswerType, handler_ptr, 3), generatedSpec(AnswerType, handler_ptr, 4), generatedSpec(AnswerType, handler_ptr, 5) },
                7 => .{ generatedSpec(AnswerType, handler_ptr, 0), generatedSpec(AnswerType, handler_ptr, 1), generatedSpec(AnswerType, handler_ptr, 2), generatedSpec(AnswerType, handler_ptr, 3), generatedSpec(AnswerType, handler_ptr, 4), generatedSpec(AnswerType, handler_ptr, 5), generatedSpec(AnswerType, handler_ptr, 6) },
                8 => .{ generatedSpec(AnswerType, handler_ptr, 0), generatedSpec(AnswerType, handler_ptr, 1), generatedSpec(AnswerType, handler_ptr, 2), generatedSpec(AnswerType, handler_ptr, 3), generatedSpec(AnswerType, handler_ptr, 4), generatedSpec(AnswerType, handler_ptr, 5), generatedSpec(AnswerType, handler_ptr, 6), generatedSpec(AnswerType, handler_ptr, 7) },
                else => unreachable,
            };
        }

        fn activeEngineContext(comptime Cap: type, ctx: anytype) *Cap.EngineContextType() {
            comptime family.assertContextType(Cap, @TypeOf(ctx));
            const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
            const EngineContextType = Cap.EngineContextType();
            const shim = family.EngineShim(ContextType, EngineContextType);
            _ = ctx._cap;
            return shim.active_engine.?;
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
            return switch (mode) {
                .resume_then_transform => if (OpPayloadType(OpTypeValue) == void) struct {
                    ctx: ?Config.ContextPtr,

                    /// Perform one zero-payload generated lexical transform op.
                    pub fn perform(self: @This()) shift.ResetError(ErrorSetType)!OpResumeType(OpTypeValue) {
                        return try Op(tag).perform(Config.Capability, self.ctx.?);
                    }
                } else struct {
                    ctx: ?Config.ContextPtr,

                    /// Perform one payload-carrying generated lexical transform op.
                    pub fn perform(self: @This(), payload: OpPayloadType(OpTypeValue)) shift.ResetError(ErrorSetType)!OpResumeType(OpTypeValue) {
                        return try Op(tag).perform(Config.Capability, self.ctx.?, payload);
                    }
                },
                .resume_or_return => if (OpPayloadType(OpTypeValue) == void) struct {
                    const Handle = @This();

                    ctx: ?Config.ContextPtr,
                    runtime: ?*shift.Runtime,
                    handlers_ptr: ?*Config.Handlers,
                    previous_eff: Config.PreviousEff,
                    outputs_ptr: ?*lexical_with.OutputBundleType(Config.Handlers),

                    /// Perform one zero-payload generated lexical choice op.
                    pub fn perform(self: Handle, comptime Continuation: type) shift.ResetError(ErrorSetType)!lexical_with.ChoiceAnswerType(Continuation) {
                        const request_state = struct {
                            threadlocal var active_handle: ?Handle = null;

                            /// Re-enter the lexical continuation after one generated choice resume.
                            pub fn apply(value: OpResumeType(OpTypeValue)) shift.ResetError(ErrorSetType)!lexical_with.ChoiceAnswerType(Continuation) {
                                const current_handle = active_handle.?;
                                return try lexical_with.continueChoice(
                                    Config.Handlers,
                                    Config.binder_index,
                                    .{
                                        .runtime = current_handle.runtime.?,
                                        .handlers_ptr = current_handle.handlers_ptr.?,
                                        .previous_eff = current_handle.previous_eff,
                                        .current_handle = current_handle,
                                        .outputs_ptr = current_handle.outputs_ptr.?,
                                    },
                                    Continuation,
                                    value,
                                );
                            }
                        };

                        const previous_handle = request_state.active_handle;
                        request_state.active_handle = self;
                        defer request_state.active_handle = previous_handle;

                        const authored = Op(tag).program(Config.Capability, self.ctx.?, request_state);
                        authored.activate();
                        defer authored.deactivate();
                        return try frontend.run(self.runtime.?, authored.prompt, authored.program);
                    }
                } else struct {
                    const Handle = @This();

                    ctx: ?Config.ContextPtr,
                    runtime: ?*shift.Runtime,
                    handlers_ptr: ?*Config.Handlers,
                    previous_eff: Config.PreviousEff,
                    outputs_ptr: ?*lexical_with.OutputBundleType(Config.Handlers),

                    /// Perform one payload-carrying generated lexical choice op.
                    pub fn perform(self: Handle, payload: OpPayloadType(OpTypeValue), comptime Continuation: type) shift.ResetError(ErrorSetType)!lexical_with.ChoiceAnswerType(Continuation) {
                        const request_state = struct {
                            threadlocal var active_handle: ?Handle = null;

                            /// Re-enter the lexical continuation after one generated choice resume.
                            pub fn apply(value: OpResumeType(OpTypeValue)) shift.ResetError(ErrorSetType)!lexical_with.ChoiceAnswerType(Continuation) {
                                const current_handle = active_handle.?;
                                return try lexical_with.continueChoice(
                                    Config.Handlers,
                                    Config.binder_index,
                                    .{
                                        .runtime = current_handle.runtime.?,
                                        .handlers_ptr = current_handle.handlers_ptr.?,
                                        .previous_eff = current_handle.previous_eff,
                                        .current_handle = current_handle,
                                        .outputs_ptr = current_handle.outputs_ptr.?,
                                    },
                                    Continuation,
                                    value,
                                );
                            }
                        };

                        const previous_handle = request_state.active_handle;
                        request_state.active_handle = self;
                        defer request_state.active_handle = previous_handle;

                        const authored = Op(tag).program(Config.Capability, self.ctx.?, payload, request_state);
                        authored.activate();
                        defer authored.deactivate();
                        return try frontend.run(self.runtime.?, authored.prompt, authored.program);
                    }
                },
                .direct_return => if (OpPayloadType(OpTypeValue) == void) struct {
                    ctx: ?Config.ContextPtr,

                    /// Perform one zero-payload generated lexical abort op.
                    pub fn abort(self: @This()) shift.ResetError(ErrorSetType)!noreturn {
                        return try Op(tag).perform(Config.Capability, self.ctx.?);
                    }
                } else struct {
                    ctx: ?Config.ContextPtr,

                    /// Perform one payload-carrying generated lexical abort op.
                    pub fn abort(self: @This(), payload: OpPayloadType(OpTypeValue)) shift.ResetError(ErrorSetType)!noreturn {
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
                /// Shared error set carried by the generated lexical descriptor.
                pub const ErrorSet = ErrorSetType;
                /// Final generated descriptor output; transform families emit final state and control families emit no extra output.
                pub const Output = if (mode == .resume_then_transform) StateType else void;

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
                    runtime: *shift.Runtime,
                    handlers_ptr: anytype,
                    previous_eff: anytype,
                    outputs_ptr: anytype,
                    comptime index: usize,
                ) HandleType(Cap, @TypeOf(ctx), @TypeOf(handlers_ptr.*), @TypeOf(previous_eff), index) {
                    _ = self;
                    var field_container = std.mem.zeroInit(HandleType(Cap, @TypeOf(ctx), @TypeOf(handlers_ptr.*), @TypeOf(previous_eff), index), .{});
                    inline for (op_specs) |SpecOp| {
                        const field_handle = switch (mode) {
                            .resume_then_transform => LexicalOpFieldHandle(@field(OpTag, opName(SpecOp)), LexicalFieldConfig(Cap, @TypeOf(ctx), @TypeOf(handlers_ptr.*), @TypeOf(previous_eff), index)){
                                .ctx = ctx,
                            },
                            .resume_or_return => LexicalOpFieldHandle(@field(OpTag, opName(SpecOp)), LexicalFieldConfig(Cap, @TypeOf(ctx), @TypeOf(handlers_ptr.*), @TypeOf(previous_eff), index)){
                                .ctx = ctx,
                                .runtime = runtime,
                                .handlers_ptr = handlers_ptr,
                                .previous_eff = previous_eff,
                                .outputs_ptr = outputs_ptr,
                            },
                            .direct_return => LexicalOpFieldHandle(@field(OpTag, opName(SpecOp)), LexicalFieldConfig(Cap, @TypeOf(ctx), @TypeOf(handlers_ptr.*), @TypeOf(previous_eff), index)){
                                .ctx = ctx,
                            },
                        };
                        @field(field_container, opName(SpecOp)) = field_handle;
                    }
                    return field_container;
                }

                /// Run one generated lexical descriptor through the existing generated-family handler path.
                pub fn run(self: @This(), comptime AnswerType: type, runtime: *shift.Runtime, comptime Body: type) shift.ResetError(ErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
                    var instance = Instance.init();
                    const result = try self_type.handle(AnswerType, runtime, &instance, self.handler, Body);
                    if (mode == .resume_then_transform) {
                        return .{
                            .output = result.state,
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
        pub fn handle(comptime AnswerType: type, runtime: *shift.Runtime, instance: anytype, handler: anytype, comptime Body: type) shift.ResetError(ErrorSetType)!if (mode == .resume_then_transform) HandleResult(AnswerType) else AnswerType {
            var handler_value = handler;
            const handler_ptr = &handler_value;
            const HandlerType = @TypeOf(handler_value);
            comptime assertHandlerBundle(mode, StateType, AnswerType, ErrorSetType, op_specs, HandlerType);

            const specs = buildSpecs(AnswerType, handler_ptr);
            const Configured = @TypeOf(internal.Program(AnswerType, AnswerType, ErrorSetType, op_specs).handlers(specs));
            const BindingsType = internal.BindingChainFor(@TypeOf(specs), AnswerType, AnswerType, ErrorSetType);
            var bindings = BindingsType.initWithToken(specs, instance.prompt.token);
            var engine_ctx = Configured.Context{ .bindings = &bindings };

            const capability_meta = struct {
                const body_tag = Body;

                /// Shared engine context type for the active generated family run.
                pub fn EngineContextType() type {
                    return Configured.Context;
                }
            };

            const sealed_contract = struct {
                const PromptTypeG = prompt_contract.Prompt(mode, AnswerType, AnswerType, ErrorSetType);
                const StateTypeG = StateType;
                const AnswerTypeG = AnswerType;
                const ErrorSetTypeG = ErrorSetType;
                const capability_decls = capability_meta;
            };
            const value = try runWithSealedEngine(
                sealed_contract,
                .{ .runtime = runtime, .prompt_token = instance.prompt.token, .engine_ctx = &engine_ctx },
                Body,
            );
            if (mode == .resume_then_transform) {
                return .{ .state = handler_value.state, .value = value };
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
                pub fn perform(comptime Cap: type, ctx: anytype) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!OpTypeValue.Resume {
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
                pub fn perform(comptime Cap: type, ctx: anytype, payload: OpTypeValue.Payload) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!OpTypeValue.Resume {
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
                pub fn perform(comptime Cap: type, ctx: anytype) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!OpTypeValue.Resume {
                    comptime family.assertContextType(Cap, @TypeOf(ctx));
                    return try activeEngineContext(Cap, ctx).perform(OpTypeValue, {});
                }

                /// Build one explicit zero-payload generated control op program.
                pub fn program(comptime Cap: type, ctx: anytype, comptime Continuation: type) @TypeOf(activeEngineContext(Cap, ctx).performProgram(OpTypeValue, {}, Continuation)) {
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
                pub fn perform(comptime Cap: type, ctx: anytype, payload: OpTypeValue.Payload) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!OpTypeValue.Resume {
                    comptime family.assertContextType(Cap, @TypeOf(ctx));
                    return try activeEngineContext(Cap, ctx).perform(OpTypeValue, payload);
                }

                /// Build one explicit payload-carrying generated control op program.
                pub fn program(comptime Cap: type, ctx: anytype, payload: OpTypeValue.Payload, comptime Continuation: type) @TypeOf(activeEngineContext(Cap, ctx).performProgram(OpTypeValue, payload, Continuation)) {
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
            pub fn exampleHarness(comptime AnswerType: type, runtime: *shift.Runtime, instance: anytype, handler: anytype, comptime Body: type) shift.ResetError(ErrorSetType)!if (mode == .resume_then_transform) HandleResult(AnswerType) else AnswerType {
                return self_type.handle(AnswerType, runtime, instance, handler, Body);
            }
        };
    };
}
