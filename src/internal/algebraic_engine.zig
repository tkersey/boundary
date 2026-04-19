const effect_ir = @import("effect_ir");
const frontend = @import("frontend_support");
const lowered_machine = @import("lowered_machine");
const lowering_api = @import("lowering_api");
const prompt_contract = @import("prompt_contract_support");
const std = @import("std");

const BuilderKind = enum {
    abort,
    choice,
    direct_transform,
    transform,
};

/// Define one closed-world resumptive transform operation.
pub fn TransformOp(
    comptime name: []const u8,
    comptime PayloadType: type,
    comptime ResumeType: type,
) type {
    return struct {
        const op_name = name;
        const mode = prompt_contract.PromptMode.resume_then_transform;
        const Payload = PayloadType;
        const Resume = ResumeType;
    };
}

/// Define one closed-world zero-or-one-resume choice operation.
pub fn ChoiceOp(
    comptime name: []const u8,
    comptime PayloadType: type,
    comptime ResumeType: type,
) type {
    return struct {
        const op_name = name;
        const mode = prompt_contract.PromptMode.resume_or_return;
        const Payload = PayloadType;
        const Resume = ResumeType;
    };
}

/// Define one closed-world abortive operation.
pub fn AbortOp(
    comptime name: []const u8,
    comptime PayloadType: type,
) type {
    return struct {
        const op_name = name;
        const mode = prompt_contract.PromptMode.direct_return;
        const Payload = PayloadType;
        const Resume = noreturn;
    };
}

/// Build a transform handler specification for a declared transform op.
pub fn handleTransform(comptime Op: type, state: anytype, comptime Impl: type) TransformSpec(Op, @TypeOf(state), Impl) {
    comptime assertOpMode(Op, .resume_then_transform, "transform");
    return .{ .state = state };
}

/// Build a direct transform handler specification for a declared transform op.
pub fn handleDirectTransform(comptime Op: type, state: anytype, comptime Impl: type) DirectTransformSpec(Op, @TypeOf(state), Impl) {
    comptime assertOpMode(Op, .resume_then_transform, "direct transform");
    return .{ .state = state };
}

/// Build a choice handler specification for a declared choice op.
pub fn handleChoice(comptime Op: type, state: anytype, comptime Impl: type) ChoiceSpec(Op, @TypeOf(state), Impl) {
    comptime assertOpMode(Op, .resume_or_return, "choice");
    return .{ .state = state };
}

/// Build an abort handler specification for a declared abort op.
pub fn handleAbort(comptime Op: type, state: anytype, comptime Impl: type) AbortSpec(Op, @TypeOf(state), Impl) {
    comptime assertOpMode(Op, .direct_return, "abort");
    return .{ .state = state };
}

fn TransformSpec(comptime Op: type, comptime StateType: type, comptime Impl: type) type {
    return struct {
        /// Public `Operation` declaration.
        pub const Operation = Op;
        /// Public `builder_kind` declaration.
        pub const builder_kind = BuilderKind.transform;
        /// Public `State` declaration.
        pub const State = StateType;
        /// Public `ImplType` declaration.
        pub const ImplType = Impl;

        state: StateType,
    };
}

fn DirectTransformSpec(comptime Op: type, comptime StateType: type, comptime Impl: type) type {
    return struct {
        /// Public `Operation` declaration.
        pub const Operation = Op;
        /// Public `builder_kind` declaration.
        pub const builder_kind = BuilderKind.direct_transform;
        /// Public `State` declaration.
        pub const State = StateType;
        /// Public `ImplType` declaration.
        pub const ImplType = Impl;

        state: StateType,
    };
}

fn ChoiceSpec(comptime Op: type, comptime StateType: type, comptime Impl: type) type {
    return struct {
        /// Public `Operation` declaration.
        pub const Operation = Op;
        /// Public `builder_kind` declaration.
        pub const builder_kind = BuilderKind.choice;
        /// Public `State` declaration.
        pub const State = StateType;
        /// Public `ImplType` declaration.
        pub const ImplType = Impl;

        state: StateType,
    };
}

fn AbortSpec(comptime Op: type, comptime StateType: type, comptime Impl: type) type {
    return struct {
        /// Public `Operation` declaration.
        pub const Operation = Op;
        /// Public `builder_kind` declaration.
        pub const builder_kind = BuilderKind.abort;
        /// Public `State` declaration.
        pub const State = StateType;
        /// Public `ImplType` declaration.
        pub const ImplType = Impl;

        state: StateType,
    };
}

fn assertOpMode(comptime Op: type, comptime expected: prompt_contract.PromptMode, comptime label: []const u8) void {
    if (!@hasDecl(Op, "mode")) @compileError("algebraic op is missing mode");
    if (!@hasDecl(Op, "Payload")) @compileError("algebraic op is missing Payload");
    if (!@hasDecl(Op, "Resume")) @compileError("algebraic op is missing Resume");
    if (Op.mode != expected) {
        @compileError("algebraic " ++ label ++ " handler requires matching op mode");
    }
}

fn assertBodyType(comptime Body: type, comptime ContextType: type, comptime ErrorSet: type, comptime Answer: type) void {
    _ = ContextType;
    _ = ErrorSet;
    _ = Answer;
    if (!@hasDecl(Body, "program") and !@hasDecl(Body, "body")) @compileError("algebraic body must declare program or body");
}

fn fnReturnMatches(comptime FnType: type, comptime ExpectedType: type) bool {
    const ReturnType = @typeInfo(FnType).@"fn".return_type.?;
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload == ExpectedType,
        else => ReturnType == ExpectedType,
    };
}

fn fnParamsMatch(comptime FnType: type, comptime param_types: []const type) bool {
    const actual = @typeInfo(FnType).@"fn".params;
    if (actual.len != param_types.len) return false;
    inline for (param_types, 0..) |ParamType, index| {
        if (actual[index].type == null or actual[index].type.? != ParamType) return false;
    }
    return true;
}

fn ReturnTypeErrorSet(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.error_set,
        else => error{},
    };
}

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn ContinuationCarrierType(comptime Continuation: anytype) type {
    return if (@TypeOf(Continuation) == type) Continuation else @TypeOf(Continuation);
}

fn continuationHasApply(comptime Continuation: anytype) bool {
    return hasDeclSafe(ContinuationCarrierType(Continuation), "apply");
}

fn ExplicitContinuationFnType(comptime Continuation: anytype) type {
    const Carrier = ContinuationCarrierType(Continuation);
    if (continuationHasApply(Continuation)) return @TypeOf(Continuation.apply);
    return switch (@typeInfo(Carrier)) {
        .@"fn" => Carrier,
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn")
            pointer.child
        else
            @compileError("explicit program continuation must declare apply(value) or be a callable function"),
        else => @compileError("explicit program continuation must declare apply(value) or be a callable function"),
    };
}

fn dummyPointer(comptime PtrType: type) PtrType {
    const pointer = @typeInfo(PtrType).pointer;
    const Child = std.meta.Child(PtrType);
    if (pointer.size == .slice) {
        return blk: {
            const base = std.mem.alignForward(usize, 1, @alignOf(Child));
            const many = @as([*]Child, @ptrFromInt(base));
            const slice = many[0..1];
            if (pointer.is_const) break :blk @as(PtrType, slice);
            break :blk @as(PtrType, @constCast(slice));
        };
    }
    return @as(PtrType, @ptrFromInt(std.mem.alignForward(usize, 1, @alignOf(Child))));
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

fn ExplicitContinuationReturnType(comptime Continuation: anytype, comptime ResumeType: type) type {
    const ContinuationFn = ExplicitContinuationFnType(Continuation);
    const params = @typeInfo(ContinuationFn).@"fn".params;
    if (params.len != 1) @compileError("explicit program continuation must accept exactly one resumed value");
    if (comptime continuationHasApply(Continuation)) {
        return @TypeOf(Continuation.apply(dummyValue(ResumeType)));
    }
    if (comptime @TypeOf(Continuation) == type) @compileError("explicit program continuations must be passed as callable values, not function types");
    return @TypeOf(Continuation(dummyValue(ResumeType)));
}

fn ExplicitContinuationErrorSet(comptime Continuation: anytype, comptime ResumeType: type) type {
    return ReturnTypeErrorSet(ExplicitContinuationReturnType(Continuation, ResumeType));
}

fn ExplicitContinuationReturnTypeWithContext(
    comptime ContextPtrType: type,
    comptime Continuation: type,
    comptime ResumeType: type,
) type {
    return @TypeOf(Continuation.apply(dummyValue(ContextPtrType), dummyValue(ResumeType)));
}

fn ExplicitContinuationErrorSetWithContext(
    comptime ContextPtrType: type,
    comptime Continuation: type,
    comptime ResumeType: type,
) type {
    return ReturnTypeErrorSet(ExplicitContinuationReturnTypeWithContext(ContextPtrType, Continuation, ResumeType));
}

fn callExplicitContinuation(
    comptime Continuation: anytype,
    resume_value: anytype,
) lowered_machine.ResetError(ExplicitContinuationErrorSet(Continuation, @TypeOf(resume_value)))!switch (@typeInfo(ExplicitContinuationReturnType(Continuation, @TypeOf(resume_value)))) {
    .error_union => |err_union| err_union.payload,
    else => ExplicitContinuationReturnType(Continuation, @TypeOf(resume_value)),
} {
    if (comptime continuationHasApply(Continuation)) {
        const ReturnType = @TypeOf(Continuation.apply(resume_value));
        if (@typeInfo(ReturnType) == .error_union) return try Continuation.apply(resume_value);
        return Continuation.apply(resume_value);
    }
    if (comptime @TypeOf(Continuation) == type) {
        @compileError("explicit program continuations must be passed as callable values, not function types");
    }
    const ReturnType = @TypeOf(Continuation(resume_value));
    if (@typeInfo(ReturnType) == .error_union) return try Continuation(resume_value);
    return Continuation(resume_value);
}

fn callExplicitContinuationWithContext(
    comptime ContextPtrType: type,
    comptime Continuation: type,
    continuation_ctx: ContextPtrType,
    resume_value: anytype,
) lowered_machine.ResetError(ExplicitContinuationErrorSetWithContext(ContextPtrType, Continuation, @TypeOf(resume_value)))!switch (@typeInfo(ExplicitContinuationReturnTypeWithContext(ContextPtrType, Continuation, @TypeOf(resume_value)))) {
    .error_union => |err_union| err_union.payload,
    else => ExplicitContinuationReturnTypeWithContext(ContextPtrType, Continuation, @TypeOf(resume_value)),
} {
    const ReturnType = @TypeOf(Continuation.apply(continuation_ctx, resume_value));
    if (@typeInfo(ReturnType) == .error_union) return try Continuation.apply(continuation_ctx, resume_value);
    return Continuation.apply(continuation_ctx, resume_value);
}

fn assertTransformImplType(comptime TransformContract: type) void {
    const StateType = TransformContract.state_type;
    const Op = TransformContract.op_type;
    const Impl = TransformContract.impl_type;
    const ContinueAnswer = TransformContract.continue_answer_type;
    _ = TransformContract.error_set_type;
    const Answer = TransformContract.answer_type;
    if (!@hasDecl(Impl, "resumeValue")) @compileError("transform handler must declare resumeValue");
    if (!@hasDecl(Impl, "afterResume")) @compileError("transform handler must declare afterResume");

    const ResumeFn = @TypeOf(Impl.resumeValue);
    if (!fnParamsMatch(ResumeFn, &.{ StateType, Op.Payload }) or !fnReturnMatches(ResumeFn, Op.Resume)) {
        @compileError("transform handler resumeValue must have type fn (State, Payload) Resume or fn (State, Payload) ResetError(ErrorSet)!Resume");
    }

    const AfterFn = @TypeOf(Impl.afterResume);
    if (!fnParamsMatch(AfterFn, &.{ StateType, ContinueAnswer }) or !fnReturnMatches(AfterFn, Answer)) {
        @compileError("transform handler afterResume must have type fn (State, ContinueAnswer) Answer or fn (State, ContinueAnswer) ResetError(ErrorSet)!Answer");
    }
}

fn assertChoiceImplType(comptime ChoiceContract: type) void {
    const StateType = ChoiceContract.state_type;
    const Op = ChoiceContract.op_type;
    const Impl = ChoiceContract.impl_type;
    const ContinueAnswer = ChoiceContract.continue_answer_type;
    _ = ChoiceContract.error_set_type;
    const Answer = ChoiceContract.answer_type;
    if (!@hasDecl(Impl, "resumeOrReturn")) @compileError("choice handler must declare resumeOrReturn");
    if (!@hasDecl(Impl, "afterResume")) @compileError("choice handler must declare afterResume");

    const DecisionType = prompt_contract.ResumeOrReturn(Op.Resume, Answer);
    const DecideFn = @TypeOf(Impl.resumeOrReturn);
    if (!fnParamsMatch(DecideFn, &.{ StateType, Op.Payload }) or !fnReturnMatches(DecideFn, DecisionType)) {
        @compileError("choice handler resumeOrReturn must have type fn (State, Payload) ResumeOrReturn or fn (State, Payload) ResetError(ErrorSet)!ResumeOrReturn");
    }

    const AfterFn = @TypeOf(Impl.afterResume);
    if (!fnParamsMatch(AfterFn, &.{ StateType, ContinueAnswer }) or !fnReturnMatches(AfterFn, Answer)) {
        @compileError("choice handler afterResume must have type fn (State, ContinueAnswer) Answer or fn (State, ContinueAnswer) ResetError(ErrorSet)!Answer");
    }
}

fn assertAbortImplType(
    comptime StateType: type,
    comptime Op: type,
    comptime Impl: type,
    comptime ErrorSet: type,
    comptime Answer: type,
) void {
    _ = ErrorSet;
    if (!@hasDecl(Impl, "directReturn")) @compileError("abort handler must declare directReturn");
    const DirectFn = @TypeOf(Impl.directReturn);
    if (!fnParamsMatch(DirectFn, &.{ StateType, Op.Payload }) or !fnReturnMatches(DirectFn, Answer)) {
        @compileError("abort handler directReturn must have type fn (State, Payload) Answer or fn (State, Payload) ResetError(ErrorSet)!Answer");
    }
}

fn assertSpecType(comptime SpecType: type, comptime Op: type, comptime ContinueAnswer: type, comptime ErrorSet: type, comptime Answer: type) void {
    if (!@hasDecl(SpecType, "Operation")) @compileError("algebraic handler spec missing Operation");
    if (!@hasDecl(SpecType, "builder_kind")) @compileError("algebraic handler spec missing builder_kind");
    if (!@hasDecl(SpecType, "State")) @compileError("algebraic handler spec missing State");
    if (!@hasDecl(SpecType, "ImplType")) @compileError("algebraic handler spec missing ImplType");
    if (SpecType.Operation != Op) @compileError("algebraic handler spec order must match Program op order");

    switch (SpecType.builder_kind) {
        .direct_transform => {
            if (Op.mode != .resume_then_transform) @compileError("direct transform builder used with non-transform op");
            assertTransformImplType(struct {
                const state_type = SpecType.State;
                const op_type = Op;
                const impl_type = SpecType.ImplType;
                const continue_answer_type = ContinueAnswer;
                const error_set_type = ErrorSet;
                const answer_type = Answer;
            });
        },
        .transform => {
            if (Op.mode != .resume_then_transform) @compileError("transform builder used with non-transform op");
            assertTransformImplType(struct {
                const state_type = SpecType.State;
                const op_type = Op;
                const impl_type = SpecType.ImplType;
                const continue_answer_type = ContinueAnswer;
                const error_set_type = ErrorSet;
                const answer_type = Answer;
            });
        },
        .choice => {
            if (Op.mode != .resume_or_return) @compileError("choice builder used with non-choice op");
            assertChoiceImplType(struct {
                const state_type = SpecType.State;
                const op_type = Op;
                const impl_type = SpecType.ImplType;
                const continue_answer_type = ContinueAnswer;
                const error_set_type = ErrorSet;
                const answer_type = Answer;
            });
        },
        .abort => {
            if (Op.mode != .direct_return) @compileError("abort builder used with non-abort op");
            assertAbortImplType(SpecType.State, Op, SpecType.ImplType, ErrorSet, Answer);
        },
    }
}

fn TupleFieldType(comptime TupleType: type, comptime index: usize) type {
    return @typeInfo(TupleType).@"struct".fields[index].type;
}

fn tupleLen(comptime TupleType: type) usize {
    return @typeInfo(TupleType).@"struct".fields.len;
}

fn PromptTypeForOp(comptime Op: type, comptime ContinueAnswer: type, comptime Answer: type, comptime ErrorSet: type) type {
    return prompt_contract.Prompt(Op.mode, ContinueAnswer, Answer, ErrorSet);
}

fn Binding(
    comptime SpecType: type,
    comptime ContinueAnswer: type,
    comptime Answer: type,
    comptime ErrorSet: type,
) type {
    const Op = SpecType.Operation;
    const StateType = SpecType.State;
    const Impl = SpecType.ImplType;
    const PromptType = PromptTypeForOp(Op, ContinueAnswer, Answer, ErrorSet);
    return struct {
        const Self = @This();
        const Prompt = PromptType;

        spec: SpecType,
        prompt: PromptType,
        prompt_identity: ?*const anyopaque = null,
        threadlocal var direct_binding: ?*Self = null;
        threadlocal var direct_payload: ?Op.Payload = null;

        fn ProgramErrorSet(comptime Continuation: anytype) type {
            return switch (SpecType.builder_kind) {
                .transform, .choice => ErrorSet || ExplicitContinuationErrorSet(Continuation, Op.Resume),
                .direct_transform, .abort => ErrorSet,
            };
        }

        fn ProgramPromptType(comptime Continuation: anytype) type {
            return PromptTypeForOp(Op, ContinueAnswer, Answer, ProgramErrorSet(Continuation));
        }

        fn ProgramErrorSetWithContext(comptime ContextPtrType: type, comptime Continuation: type) type {
            return ErrorSet || ReturnTypeErrorSet(@TypeOf(Continuation.apply(dummyValue(ContextPtrType), dummyValue(Op.Resume))));
        }

        fn ProgramPromptTypeWithContext(comptime ContextPtrType: type, comptime Continuation: type) type {
            const ReturnType = @TypeOf(Continuation.apply(dummyValue(ContextPtrType), dummyValue(Op.Resume)));
            const ContinueAnswerType = switch (@typeInfo(ReturnType)) {
                .error_union => |err_union| err_union.payload,
                else => ReturnType,
            };
            return PromptTypeForOp(Op, ContinueAnswerType, Answer, ProgramErrorSetWithContext(ContextPtrType, Continuation));
        }

        fn activePrompt(self: *const Self) *const PromptType {
            if (self.prompt_identity) |prompt| return @ptrCast(@alignCast(prompt));
            return &self.prompt;
        }

        fn promptRef(self: *@This(), comptime Continuation: anytype) *const ProgramPromptType(Continuation) {
            // Prompt layout stays token-only, so the shared live prompt identity can be widened safely.
            return @ptrCast(self.activePrompt());
        }

        fn promptRefWithContext(self: *@This(), comptime ContextPtrType: type, comptime Continuation: type) *const ProgramPromptTypeWithContext(ContextPtrType, Continuation) {
            return @ptrCast(self.activePrompt());
        }

        /// Build one binding with a fresh prompt token.
        pub fn init(spec: SpecType) @This() {
            return .{
                .spec = spec,
                .prompt = PromptType.init(),
            };
        }

        /// Build one binding that reuses an externally supplied prompt token.
        pub fn initWithToken(spec: SpecType, token: prompt_contract.PromptToken) @This() {
            return .{
                .spec = spec,
                .prompt = .{ .token = token },
            };
        }

        /// Build one binding that reuses an externally supplied prompt identity and token.
        pub fn initWithPrompt(spec: SpecType, prompt: anytype) @This() {
            return .{
                .spec = spec,
                .prompt = .{ .token = prompt.token },
                .prompt_identity = @ptrCast(prompt),
            };
        }

        fn currentDirectPayload() Op.Payload {
            if (comptime Op.Payload == void) return {};
            return direct_payload.?;
        }

        fn HandlerCarrier() type {
            return struct {
                binding: *Self,
                payload: Op.Payload,
            };
        }

        fn supportedAuthoredPayloadCodec() ?effect_ir.LocalCodec {
            return switch (Op.Payload) {
                void => .unit,
                bool => .bool,
                i32 => .i32,
                usize => .usize,
                []const u8 => .string,
                else => null,
            };
        }

        fn supportedAuthoredResumeCodec() ?effect_ir.LocalCodec {
            return switch (Op.Resume) {
                void => .unit,
                bool => .bool,
                i32 => .i32,
                usize => .usize,
                []const u8 => .string,
                else => null,
            };
        }

        fn supportedAuthoredResultType() ?type {
            return switch (Answer) {
                void, bool, i32, usize, []const u8 => Answer,
                else => null,
            };
        }

        fn encodeAuthoredPayload(comptime codec: effect_ir.LocalCodec, payload: Op.Payload) lowered_machine.ProgramValue {
            return switch (codec) {
                .unit => .none,
                .bool => .{ .bool = payload },
                .i32 => .{ .i32 = payload },
                .usize => .{ .usize = payload },
                .string => .{ .string = payload },
                .string_list => unreachable,
            };
        }

        fn authoredCompiledProgram() ?lowering_api.ProgramPlan {
            _ = supportedAuthoredPayloadCodec() orelse return null;
            _ = supportedAuthoredResultType() orelse return null;
            return lowering_api.authoredBoundProgramPlan(switch (SpecType.builder_kind) {
                .abort => "authored.abort.bound_program",
                .choice => "authored.choice.bound_program",
                .transform => "authored.transform.bound_program",
                .direct_transform => return null,
            }, Op.Payload, Op.Resume, Answer, switch (SpecType.builder_kind) {
                .abort => .abort,
                .choice => .choice,
                .transform => .transform,
                .direct_transform => unreachable,
            });
        }

        fn AuthoredCompiledHandlers(comptime Continuation: anytype) type {
            const BindingType = Self;
            return switch (SpecType.builder_kind) {
                .abort => if (Op.Payload == void) struct {
                    authored: struct {
                        binding: *BindingType,

                        /// Dispatch one zero-payload authored abort operation through the live binding.
                        pub fn dispatch(self: *@This()) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callDirectReturn(self.binding.spec, {});
                        }
                    },
                } else struct {
                    authored: struct {
                        binding: *BindingType,

                        /// Dispatch one payload-carrying authored abort operation through the live binding.
                        pub fn dispatch(self: *@This(), payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callDirectReturn(self.binding.spec, payload);
                        }
                    },
                },
                .transform => if (Op.Payload == void) struct {
                    authored: struct {
                        binding: *BindingType,

                        /// Dispatch one zero-payload authored transform operation through the live binding.
                        pub fn dispatch(self: *@This()) lowered_machine.ResetError(ErrorSet)!Op.Resume {
                            return try BindingType.callResumeValue(self.binding.spec, {});
                        }

                        /// Finish one resumed authored transform by running the explicit continuation and after-resume hook.
                        pub fn afterDispatch(self: *@This(), resume_value: Op.Resume) lowered_machine.ResetError(ErrorSet || ExplicitContinuationErrorSet(Continuation, Op.Resume))!Answer {
                            const continued = try callExplicitContinuation(Continuation, resume_value);
                            return try BindingType.callAfterResume(self.binding.spec, continued);
                        }
                    },
                } else struct {
                    authored: struct {
                        binding: *BindingType,

                        /// Dispatch one payload-carrying authored transform operation through the live binding.
                        pub fn dispatch(self: *@This(), payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!Op.Resume {
                            return try BindingType.callResumeValue(self.binding.spec, payload);
                        }

                        /// Finish one resumed authored transform by running the explicit continuation and after-resume hook.
                        pub fn afterDispatch(self: *@This(), resume_value: Op.Resume) lowered_machine.ResetError(ErrorSet || ExplicitContinuationErrorSet(Continuation, Op.Resume))!Answer {
                            const continued = try callExplicitContinuation(Continuation, resume_value);
                            return try BindingType.callAfterResume(self.binding.spec, continued);
                        }
                    },
                },
                .choice => if (Op.Payload == void) struct {
                    authored: struct {
                        binding: *BindingType,

                        /// Dispatch one zero-payload authored choice operation through the live binding.
                        pub fn dispatch(self: *@This()) lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
                            return try BindingType.callResumeOrReturn(self.binding.spec, {});
                        }

                        /// Finish one resumed authored choice by running the explicit continuation and after-resume hook.
                        pub fn afterDispatch(self: *@This(), resume_value: Op.Resume) lowered_machine.ResetError(ErrorSet || ExplicitContinuationErrorSet(Continuation, Op.Resume))!Answer {
                            const continued = try callExplicitContinuation(Continuation, resume_value);
                            return try BindingType.callAfterResume(self.binding.spec, continued);
                        }
                    },
                } else struct {
                    authored: struct {
                        binding: *BindingType,

                        /// Dispatch one payload-carrying authored choice operation through the live binding.
                        pub fn dispatch(self: *@This(), payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
                            return try BindingType.callResumeOrReturn(self.binding.spec, payload);
                        }

                        /// Finish one resumed authored choice by running the explicit continuation and after-resume hook.
                        pub fn afterDispatch(self: *@This(), resume_value: Op.Resume) lowered_machine.ResetError(ErrorSet || ExplicitContinuationErrorSet(Continuation, Op.Resume))!Answer {
                            const continued = try callExplicitContinuation(Continuation, resume_value);
                            return try BindingType.callAfterResume(self.binding.spec, continued);
                        }
                    },
                },
                .direct_transform => @compileError("compiled authored program path is unavailable for this binding"),
            };
        }

        fn AuthoredCompiledHandlersWithContext(comptime ContextPtrType: type, comptime Continuation: type) type {
            const BindingType = Self;
            return switch (SpecType.builder_kind) {
                .choice => if (Op.Payload == void) struct {
                    authored: struct {
                        binding: *BindingType,
                        continuation_ctx: ContextPtrType,

                        /// Dispatch one zero-payload authored contextual choice operation through the live binding.
                        pub fn dispatch(self: *@This()) lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
                            return try BindingType.callResumeOrReturn(self.binding.spec, {});
                        }

                        /// Finish one resumed authored contextual choice by running the contextual continuation and after-resume hook.
                        pub fn afterDispatch(self: *@This(), resume_value: Op.Resume) lowered_machine.ResetError(ErrorSet || ExplicitContinuationErrorSetWithContext(ContextPtrType, Continuation, Op.Resume))!Answer {
                            const continued = try callExplicitContinuationWithContext(ContextPtrType, Continuation, self.continuation_ctx, resume_value);
                            return try BindingType.callAfterResume(self.binding.spec, continued);
                        }
                    },
                } else struct {
                    authored: struct {
                        binding: *BindingType,
                        continuation_ctx: ContextPtrType,

                        /// Dispatch one payload-carrying authored contextual choice operation through the live binding.
                        pub fn dispatch(self: *@This(), payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
                            return try BindingType.callResumeOrReturn(self.binding.spec, payload);
                        }

                        /// Finish one resumed authored contextual choice by running the contextual continuation and after-resume hook.
                        pub fn afterDispatch(self: *@This(), resume_value: Op.Resume) lowered_machine.ResetError(ErrorSet || ExplicitContinuationErrorSetWithContext(ContextPtrType, Continuation, Op.Resume))!Answer {
                            const continued = try callExplicitContinuationWithContext(ContextPtrType, Continuation, self.continuation_ctx, resume_value);
                            return try BindingType.callAfterResume(self.binding.spec, continued);
                        }
                    },
                },
                else => @compileError("compiled authored contextual program path is currently available only for choice bindings"),
            };
        }

        const ActiveCarrierNode = struct {
            prompt_key: usize,
            carrier: HandlerCarrier(),
            previous: ?*ActiveCarrierNode = null,
        };

        threadlocal var active_carrier_head: ?*ActiveCarrierNode = null;

        fn activeCarrierKey(prompt: anytype) usize {
            return @intFromPtr(prompt);
        }

        fn pushActiveCarrier(node: *?ActiveCarrierNode, prompt: anytype, carrier: HandlerCarrier()) void {
            node.* = .{
                .prompt_key = activeCarrierKey(prompt),
                .carrier = carrier,
                .previous = active_carrier_head,
            };
            active_carrier_head = &node.*.?;
        }

        fn popActiveCarrier(node: *?ActiveCarrierNode, prompt: anytype) void {
            const active_node = &node.*.?;
            if (active_carrier_head != active_node or active_node.prompt_key != activeCarrierKey(prompt)) unreachable;
            active_carrier_head = active_node.previous;
            node.* = null;
        }

        fn activeCarrier(prompt: anytype) *HandlerCarrier() {
            const key = activeCarrierKey(prompt);
            var node = active_carrier_head.?;
            while (true) {
                if (node.prompt_key == key) return &node.carrier;
                node = node.previous.?;
            }
        }

        fn AuthoredProgramType(comptime Continuation: anytype) type {
            const ProgramPrompt = ProgramPromptType(Continuation);
            return struct {
                active_node: ?ActiveCarrierNode = null,
                carrier: HandlerCarrier(),
                prompt: *const ProgramPrompt,
                program: frontend.Program(ProgramPrompt),
                /// Prompt mode carried by this authored program witness.
                pub const authored_prompt_mode = Op.mode;
                /// Payload type accepted by the authored operation carrier.
                pub const AuthoredPayloadType = Op.Payload;
                /// Resume type emitted by the authored operation carrier.
                pub const AuthoredResumeType = Op.Resume;
                /// Continuation answer type consumed by the binding after-resume hook.
                pub const AuthoredContinueAnswerType = ContinueAnswer;
                /// Final answer type produced by the authored program.
                pub const AuthoredAnswerType = Answer;
                /// Whether this authored program has a semantic compiled ProgramPlan path.
                pub const has_compiled_plan = authoredCompiledProgram() != null;

                /// Install the explicit handler carrier onto the authored program before execution.
                pub fn activate(self: *const @This()) void {
                    const mutable_self: *@This() = @constCast(self);
                    Self.pushActiveCarrier(&mutable_self.active_node, self.prompt, self.carrier);
                }

                /// Clear the explicit handler carrier after authored execution completes.
                pub fn deactivate(self: *const @This()) void {
                    const mutable_self: *@This() = @constCast(self);
                    Self.popActiveCarrier(&mutable_self.active_node, self.prompt);
                }

                /// Return the compiled ProgramPlan when this authored carrier can lower semantically.
                pub fn compiledPlan() ?lowering_api.ProgramPlan {
                    return authoredCompiledProgram();
                }

                /// Execute this authored program through its compiled ProgramPlan when available.
                pub fn runCompiled(self: @This(), runtime: *lowered_machine.Runtime) lowered_machine.ResetError(ErrorSet || ExplicitContinuationErrorSet(Continuation, Op.Resume))!Answer {
                    const compiled_plan = comptime authoredCompiledProgram() orelse
                        @compileError("compiled authored program path is unavailable for this binding");
                    var handlers: AuthoredCompiledHandlers(Continuation) = .{
                        .authored = .{ .binding = self.carrier.binding },
                    };
                    const payload_codec = comptime supportedAuthoredPayloadCodec().?;
                    const args = if (payload_codec == .unit)
                        &.{}
                    else
                        &.{encodeAuthoredPayload(payload_codec, self.carrier.payload)};
                    return (lowering_api.runExecutablePlanWithArgs(runtime, compiled_plan, &handlers, args) catch |err| return @errorCast(err)).value;
                }
            };
        }

        fn AuthoredProgramWithContextType(comptime ContextPtrType: type, comptime Continuation: type) type {
            const ProgramPrompt = ProgramPromptTypeWithContext(ContextPtrType, Continuation);
            return struct {
                active_node: ?ActiveCarrierNode = null,
                carrier: HandlerCarrier(),
                prompt: *const ProgramPrompt,
                program: frontend.Program(ProgramPrompt),
                continuation_ctx: ContextPtrType,
                /// Prompt mode carried by this authored contextual program witness.
                pub const authored_prompt_mode = Op.mode;
                /// Payload type accepted by the authored contextual operation carrier.
                pub const AuthoredPayloadType = Op.Payload;
                /// Resume type emitted by the authored contextual operation carrier.
                pub const AuthoredResumeType = Op.Resume;
                /// Continuation answer type consumed by the binding after-resume hook.
                pub const AuthoredContinueAnswerType = switch (@typeInfo(@TypeOf(Continuation.apply(dummyValue(ContextPtrType), dummyValue(Op.Resume))))) {
                    .error_union => |err_union| err_union.payload,
                    else => @TypeOf(Continuation.apply(dummyValue(ContextPtrType), dummyValue(Op.Resume))),
                };
                /// Final answer type produced by the authored contextual program.
                pub const AuthoredAnswerType = Answer;
                /// Whether this authored contextual program has a semantic compiled ProgramPlan path.
                pub const has_compiled_plan = authoredCompiledProgram() != null and SpecType.builder_kind == .choice;

                /// Install the explicit handler carrier onto the authored choice program before execution.
                pub fn activate(self: *const @This()) void {
                    const mutable_self: *@This() = @constCast(self);
                    Self.pushActiveCarrier(&mutable_self.active_node, self.prompt, self.carrier);
                }

                /// Clear the explicit handler carrier after authored choice execution completes.
                pub fn deactivate(self: *const @This()) void {
                    const mutable_self: *@This() = @constCast(self);
                    Self.popActiveCarrier(&mutable_self.active_node, self.prompt);
                }

                /// Return the compiled ProgramPlan when this authored contextual carrier can lower semantically.
                pub fn compiledPlan() ?lowering_api.ProgramPlan {
                    if (SpecType.builder_kind != .choice) return null;
                    return authoredCompiledProgram();
                }

                /// Execute this authored contextual program through its compiled ProgramPlan when available.
                pub fn runCompiled(self: @This(), runtime: *lowered_machine.Runtime) lowered_machine.ResetError(ErrorSet || ExplicitContinuationErrorSetWithContext(ContextPtrType, Continuation, Op.Resume))!Answer {
                    if (SpecType.builder_kind != .choice) {
                        @compileError("compiled authored contextual program path is unavailable for this binding");
                    }
                    const compiled_plan = comptime authoredCompiledProgram() orelse
                        @compileError("compiled authored contextual program path is unavailable for this binding");
                    var handlers: AuthoredCompiledHandlersWithContext(ContextPtrType, Continuation) = .{
                        .authored = .{
                            .binding = self.carrier.binding,
                            .continuation_ctx = self.continuation_ctx,
                        },
                    };
                    const payload_codec = comptime supportedAuthoredPayloadCodec().?;
                    const args = if (payload_codec == .unit)
                        &.{}
                    else
                        &.{encodeAuthoredPayload(payload_codec, self.carrier.payload)};
                    return (lowering_api.runExecutablePlanWithArgs(runtime, compiled_plan, &handlers, args) catch |err| return @errorCast(err)).value;
                }
            };
        }

        fn callResumeValue(spec: SpecType, payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!Op.Resume {
            const ResumeFn = @TypeOf(Impl.resumeValue);
            if (ResumeFn == fn (StateType, Op.Payload) Op.Resume) return Impl.resumeValue(spec.state, payload);
            return try Impl.resumeValue(spec.state, payload);
        }

        fn callAfterResume(spec: SpecType, answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
            const AfterFn = @TypeOf(Impl.afterResume);
            if (AfterFn == fn (StateType, ContinueAnswer) Answer) return Impl.afterResume(spec.state, answer);
            return try Impl.afterResume(spec.state, answer);
        }

        fn callResumeOrReturn(spec: SpecType, payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
            const DecideFn = @TypeOf(Impl.resumeOrReturn);
            if (DecideFn == fn (StateType, Op.Payload) prompt_contract.ResumeOrReturn(Op.Resume, Answer)) return Impl.resumeOrReturn(spec.state, payload);
            return try Impl.resumeOrReturn(spec.state, payload);
        }

        fn callDirectReturn(spec: SpecType, payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!Answer {
            const DirectFn = @TypeOf(Impl.directReturn);
            if (DirectFn == fn (StateType, Op.Payload) Answer) return Impl.directReturn(spec.state, payload);
            return try Impl.directReturn(spec.state, payload);
        }

        /// Perform one bound operation under the binding's prompt.
        pub fn perform(self: *@This(), payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!Op.Resume {
            const BindingType = @This();
            return switch (SpecType.builder_kind) {
                .direct_transform => try BindingType.callResumeValue(self.spec, payload),
                .transform => blk: {
                    const resume_value = try BindingType.callResumeValue(self.spec, payload);
                    const handler = struct {
                        /// Complete the enclosing answer after one transform resume from the live binding.
                        pub fn afterResume(binding: *BindingType, answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(binding.spec, answer);
                        }
                    };

                    break :blk try frontend.transformWithBorrowedAfterContext(Op.Resume, self.activePrompt(), resume_value, self, handler);
                },
                .choice => blk: {
                    const decision = try BindingType.callResumeOrReturn(self.spec, payload);
                    const handler = struct {
                        /// Complete the enclosing answer after one choice resume from the live binding.
                        pub fn afterResume(binding: *BindingType, answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(binding.spec, answer);
                        }
                    };

                    break :blk try frontend.choiceWithBorrowedAfterContext(Op.Resume, self.activePrompt(), decision, self, handler);
                },
                .abort => {
                    const Carrier = HandlerCarrier();
                    var carrier = Carrier{ .binding = self, .payload = payload };
                    const handler = struct {
                        /// Convert the explicit abort carrier into the enclosing answer.
                        pub fn directReturn(ctx: *Carrier) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callDirectReturn(ctx.binding.spec, ctx.payload);
                        }
                    };

                    return try frontend.abortWithContext(self.activePrompt(), &carrier, handler);
                },
            };
        }

        /// Build one explicit frontend program for the bound operation and continuation.
        pub fn program(self: *@This(), payload: Op.Payload, comptime Continuation: anytype) AuthoredProgramType(Continuation) {
            const BindingType = @This();
            return switch (SpecType.builder_kind) {
                .direct_transform => @compileError("direct transform bindings do not support explicit program construction"),
                .transform => blk: {
                    const ProgramPrompt = ProgramPromptType(Continuation);
                    const handler = struct {
                        /// Supply the resumptive value for one explicit transform op from the explicit carrier.
                        pub fn resumeValue(prompt: *const ProgramPrompt) lowered_machine.ResetError(ErrorSet)!Op.Resume {
                            const carrier = BindingType.activeCarrier(prompt);
                            return try BindingType.callResumeValue(carrier.binding.spec, carrier.payload);
                        }

                        /// Complete the enclosing answer after one explicit transform resume from the explicit carrier.
                        pub fn afterResume(prompt: *const ProgramPrompt, answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            const carrier = BindingType.activeCarrier(prompt);
                            return try BindingType.callAfterResume(carrier.binding.spec, answer);
                        }
                    };
                    break :blk .{
                        .carrier = .{ .binding = self, .payload = payload },
                        .prompt = self.promptRef(Continuation),
                        .program = frontend.transformProgramWithContext(ProgramPrompt, Op.Resume, self.promptRef(Continuation), handler, Continuation),
                    };
                },
                .choice => blk: {
                    const ProgramPrompt = ProgramPromptType(Continuation);
                    const handler = struct {
                        /// Decide whether one explicit choice op resumes or returns now from the explicit carrier.
                        pub fn resumeOrReturn(prompt: *const ProgramPrompt) lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
                            const carrier = BindingType.activeCarrier(prompt);
                            return try BindingType.callResumeOrReturn(carrier.binding.spec, carrier.payload);
                        }

                        /// Complete the enclosing answer after one explicit choice resume from the explicit carrier.
                        pub fn afterResume(prompt: *const ProgramPrompt, answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            const carrier = BindingType.activeCarrier(prompt);
                            return try BindingType.callAfterResume(carrier.binding.spec, answer);
                        }
                    };
                    break :blk .{
                        .carrier = .{ .binding = self, .payload = payload },
                        .prompt = self.promptRef(Continuation),
                        .program = frontend.choiceProgramWithHandlerContext(ProgramPrompt, Op.Resume, self.promptRef(Continuation), handler, Continuation),
                    };
                },
                .abort => blk: {
                    const handler = struct {
                        /// Convert one explicit abort payload into the enclosing answer from the explicit carrier.
                        pub fn directReturn(prompt: *PromptType) lowered_machine.ResetError(ErrorSet)!Answer {
                            const carrier = BindingType.activeCarrier(prompt);
                            return try BindingType.callDirectReturn(carrier.binding.spec, carrier.payload);
                        }
                    };
                    break :blk .{
                        .carrier = .{ .binding = self, .payload = payload },
                        .prompt = self.promptRef(Continuation),
                        .program = frontend.abortProgramWithContext(PromptType, @constCast(self.activePrompt()), handler),
                    };
                },
            };
        }

        /// Build one explicit frontend choice program with one runtime continuation context.
        pub fn programWithContext(self: *@This(), payload: Op.Payload, continuation_ctx: anytype, comptime Continuation: type) AuthoredProgramWithContextType(@TypeOf(continuation_ctx), Continuation) {
            const BindingType = @This();
            if (SpecType.builder_kind != .choice) @compileError("programWithContext currently supports only choice bindings");
            const ProgramPrompt = ProgramPromptTypeWithContext(@TypeOf(continuation_ctx), Continuation);
            const handler = struct {
                /// Decide whether one explicit choice op resumes or returns now from the explicit carrier.
                pub fn resumeOrReturn(prompt: *const ProgramPrompt) lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
                    const carrier = BindingType.activeCarrier(prompt);
                    return try BindingType.callResumeOrReturn(carrier.binding.spec, carrier.payload);
                }

                /// Complete the enclosing answer after one explicit choice resume from the explicit carrier.
                pub fn afterResume(prompt: *const ProgramPrompt, answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                    const carrier = BindingType.activeCarrier(prompt);
                    return try BindingType.callAfterResume(carrier.binding.spec, answer);
                }
            };
            return .{
                .carrier = .{ .binding = self, .payload = payload },
                .prompt = self.promptRefWithContext(@TypeOf(continuation_ctx), Continuation),
                .continuation_ctx = continuation_ctx,
                .program = frontend.choiceProgramWithContexts(
                    ProgramPrompt,
                    Op.Resume,
                    self.promptRefWithContext(@TypeOf(continuation_ctx), Continuation),
                    handler,
                    continuation_ctx,
                    Continuation,
                ),
            };
        }

        /// Build one explicit frontend program that closes over this binding directly.
        pub fn directProgram(self: *@This(), payload: Op.Payload, comptime Continuation: anytype) frontend.Program(ProgramPromptType(Continuation)) {
            const BindingType = @This();
            direct_binding = self;
            direct_payload = payload;
            return switch (SpecType.builder_kind) {
                .direct_transform => @compileError("direct transform bindings do not support explicit program construction"),
                .transform => blk: {
                    const ProgramPrompt = ProgramPromptType(Continuation);
                    const handler = struct {
                        /// Supply the resumptive value for one direct explicit transform op.
                        pub fn resumeValue() lowered_machine.ResetError(ErrorSet)!Op.Resume {
                            return try BindingType.callResumeValue(BindingType.direct_binding.?.spec, BindingType.currentDirectPayload());
                        }

                        /// Complete the enclosing answer after one direct explicit transform resume.
                        pub fn afterResume(answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(BindingType.direct_binding.?.spec, answer);
                        }
                    };

                    break :blk frontend.transformProgram(ProgramPrompt, Op.Resume, handler, Continuation);
                },
                .choice => blk: {
                    const ProgramPrompt = ProgramPromptType(Continuation);
                    const handler = struct {
                        /// Decide whether one direct explicit choice op resumes or returns now.
                        pub fn resumeOrReturn() lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
                            return try BindingType.callResumeOrReturn(BindingType.direct_binding.?.spec, BindingType.currentDirectPayload());
                        }

                        /// Complete the enclosing answer after one direct explicit choice resume.
                        pub fn afterResume(answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(BindingType.direct_binding.?.spec, answer);
                        }
                    };

                    break :blk frontend.choiceProgram(ProgramPrompt, Op.Resume, handler, Continuation);
                },
                .abort => blk: {
                    const handler = struct {
                        /// Convert one direct explicit abort payload into the enclosing answer.
                        pub fn directReturn() lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callDirectReturn(BindingType.direct_binding.?.spec, BindingType.currentDirectPayload());
                        }
                    };

                    break :blk frontend.abortProgram(PromptType, handler);
                },
            };
        }
    };
}

fn BindingAtType(
    comptime SpecsTupleType: type,
    comptime ContinueAnswer: type,
    comptime Answer: type,
    comptime ErrorSet: type,
    comptime index: usize,
) type {
    return Binding(TupleFieldType(SpecsTupleType, index), ContinueAnswer, Answer, ErrorSet);
}

fn BindingChainType(
    comptime SpecsTupleType: type,
    comptime ContinueAnswer: type,
    comptime Answer: type,
    comptime ErrorSet: type,
    comptime index: usize,
) type {
    if (index == tupleLen(SpecsTupleType)) {
        return struct {
            /// Build an empty binding chain terminator.
            pub fn init(_: SpecsTupleType) @This() {
                return .{};
            }

            /// Build an empty binding chain terminator for a reused prompt token.
            pub fn initWithToken(_: SpecsTupleType, _: prompt_contract.PromptToken) @This() {
                return .{};
            }

            /// Build an empty binding chain terminator for a reused prompt identity.
            pub fn initWithPrompt(_: SpecsTupleType, _: anytype) @This() {
                return .{};
            }

            /// Resolve one binding pointer from the empty chain terminator.
            pub fn bindingPtr(_: *@This(), comptime target: usize) *BindingAtType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, target) {
                @compileError("invalid algebraic binding index");
            }
        };
    }

    const CurrentBinding = BindingAtType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, index);
    const NextChain = BindingChainType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, index + 1);
    return struct {
        current: CurrentBinding,
        next: NextChain,

        /// Build one binding chain with fresh prompt tokens.
        pub fn init(specs: SpecsTupleType) @This() {
            return .{
                .current = CurrentBinding.init(specs[index]),
                .next = NextChain.init(specs),
            };
        }

        /// Build one binding chain whose bindings all share the supplied prompt token.
        pub fn initWithToken(specs: SpecsTupleType, token: prompt_contract.PromptToken) @This() {
            return .{
                .current = CurrentBinding.initWithToken(specs[index], token),
                .next = NextChain.initWithToken(specs, token),
            };
        }

        /// Build one binding chain whose bindings all share one live prompt identity.
        pub fn initWithPrompt(specs: SpecsTupleType, prompt: anytype) @This() {
            return .{
                .current = CurrentBinding.initWithPrompt(specs[index], prompt),
                .next = NextChain.initWithPrompt(specs, prompt),
            };
        }

        /// Resolve one binding pointer from the chain by compile-time index.
        pub fn bindingPtr(self: *@This(), comptime target: usize) *BindingAtType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, target) {
            if (target == index) return &self.current;
            return self.next.bindingPtr(target);
        }
    };
}

/// Resolve the internal binding type for one handler spec and answer/error contract.
pub fn BindingFor(
    comptime SpecType: type,
    comptime ContinueAnswer: type,
    comptime Answer: type,
    comptime ErrorSet: type,
) type {
    return Binding(SpecType, ContinueAnswer, Answer, ErrorSet);
}

/// Resolve the internal binding-chain type for one spec tuple and answer/error contract.
pub fn BindingChainFor(
    comptime SpecsTupleType: type,
    comptime ContinueAnswer: type,
    comptime Answer: type,
    comptime ErrorSet: type,
) type {
    return BindingChainType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, 0);
}

/// Build a closed-world algebraic program over the existing one-shot prompt runtime.
pub fn Program(
    comptime ContinueAnswer: type,
    comptime Answer: type,
    comptime ErrorSet: type,
    comptime ops: anytype,
) type {
    return struct {
        const program_ops = ops;
        const OpCount = ops.len;

        fn findOpIndex(comptime Op: type) usize {
            inline for (program_ops, 0..) |candidate, index| {
                if (candidate == Op) return index;
            }
            @compileError("algebraic Program does not include the requested op");
        }

        fn BodyPromptType() type {
            if (OpCount == 0) return prompt_contract.Prompt(.resume_then_transform, Answer, Answer, ErrorSet);
            const first_mode = program_ops[0].mode;
            inline for (program_ops, 0..) |Op, index| {
                if (index == 0) continue;
                if (Op.mode != first_mode) {
                    @compileError("algebraic body(...) support requires zero ops or all declared ops to share one prompt mode");
                }
            }
            return prompt_contract.Prompt(first_mode, Answer, Answer, ErrorSet);
        }

        fn Configured(comptime SpecsTupleType: type) type {
            comptime {
                if (tupleLen(SpecsTupleType) != OpCount) {
                    @compileError("algebraic Program.handlers expects one spec per op in declaration order");
                }
                for (program_ops, 0..) |Op, index| {
                    assertSpecType(TupleFieldType(SpecsTupleType, index), Op, ContinueAnswer, ErrorSet, Answer);
                }
            }
            const BindingsType = BindingChainType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, 0);
            return struct {
                specs: SpecsTupleType,

                /// Pointer-sized execution context for one configured program instance.
                pub const Context = struct {
                    bindings: *BindingsType,

                    /// Perform one declared operation with its payload.
                    pub fn perform(
                        self: *Context,
                        comptime Op: type,
                        payload: Op.Payload,
                    ) lowered_machine.ResetError(ErrorSet)!Op.Resume {
                        const index = comptime findOpIndex(Op);
                        return try self.bindings.bindingPtr(index).perform(payload);
                    }

                    /// Build one explicit program for a declared operation and continuation.
                    pub fn performProgram(
                        self: *Context,
                        comptime Op: type,
                        payload: Op.Payload,
                        comptime Continuation: anytype,
                    ) BindingAtType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, findOpIndex(Op)).AuthoredProgramType(Continuation) {
                        const index = comptime findOpIndex(Op);
                        const binding = self.bindings.bindingPtr(index);
                        return binding.program(payload, Continuation);
                    }

                    /// Build one explicit program for a declared choice operation and one runtime continuation context.
                    pub fn performProgramWithContext(
                        self: *Context,
                        comptime Op: type,
                        payload: Op.Payload,
                        continuation_ctx: anytype,
                        comptime Continuation: type,
                    ) BindingAtType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, findOpIndex(Op)).AuthoredProgramWithContextType(@TypeOf(continuation_ctx), Continuation) {
                        const index = comptime findOpIndex(Op);
                        const binding = self.bindings.bindingPtr(index);
                        return binding.programWithContext(payload, continuation_ctx, Continuation);
                    }
                };

                /// Run the configured program under the supplied runtime.
                pub fn run(
                    self: @This(),
                    runtime: anytype,
                    comptime Body: type,
                ) lowered_machine.ResetError(ErrorSet)!Answer {
                    comptime assertBodyType(Body, Context, ErrorSet, Answer);
                    var bindings = BindingsType.init(self.specs);
                    var ctx = Context{ .bindings = &bindings };
                    if (comptime @hasDecl(Body, "program")) {
                        var authored = Body.program(&ctx);
                        if (@hasDecl(@TypeOf(authored), "has_compiled_plan") and
                            @TypeOf(authored).has_compiled_plan)
                        {
                            return try authored.runCompiled(runtime);
                        }
                        authored.activate();
                        defer authored.deactivate();
                        return try frontend.run(runtime, authored.prompt, authored.program);
                    }

                    const PromptType = BodyPromptType();
                    var prompt = PromptType.init();
                    if (OpCount != 0) {
                        bindings = BindingsType.initWithToken(self.specs, prompt.token);
                        ctx = .{ .bindings = &bindings };
                    }
                    return try frontend.run(runtime, &prompt, frontend.computeProgramWithContext(PromptType, &ctx, struct {
                        fn invoke(active_ctx: *Context) lowered_machine.ResetError(ErrorSet)!Answer {
                            const BodyFn = @TypeOf(Body.body);
                            const ReturnType = @typeInfo(BodyFn).@"fn".return_type.?;
                            if (@typeInfo(ReturnType) != .error_union) return Body.body(active_ctx);
                            return try Body.body(active_ctx);
                        }
                    }.invoke));
                }
            };
        }

        /// Bind one handler specification per declared operation in declaration order.
        pub fn handlers(specs: anytype) Configured(@TypeOf(specs)) {
            return .{ .specs = specs };
        }
    };
}

test "descriptor shells stay zero-sized" {
    const transform_op = TransformOp("transform", i32, i32);
    const choice_op = ChoiceOp("choice", i32, i32);
    const abort_op = AbortOp("abort", []const u8);
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(transform_op));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(choice_op));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(abort_op));
}

test "stateless handler spec stays zero-sized" {
    const ping = TransformOp("ping", void, i32);
    const no_state = struct {};
    const spec = handleTransform(ping, no_state{}, struct {
        /// Supply the transform witness value.
        pub fn resumeValue(_: no_state, _: void) i32 {
            return 41;
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    });
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(@TypeOf(spec)));
}

test "generated context stays pointer-sized" {
    const ping = TransformOp("ping", void, i32);
    const program = Program(i32, i32, error{}, .{ping});
    const no_state = struct {};
    const Configured = @TypeOf(program.handlers(.{
        handleTransform(ping, no_state{}, struct {
            /// Supply the transform witness value.
            pub fn resumeValue(_: no_state, _: void) i32 {
                return 0;
            }
            /// Preserve the resumed answer unchanged.
            pub fn afterResume(_: no_state, answer: i32) i32 {
                return answer;
            }
        }),
    }));
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(Configured.Context));
}

test "configured binding chain stores direct bindings" {
    const ping = TransformOp("ping", void, i32);
    const no_state = struct {};
    const program = Program(i32, i32, error{}, .{ping});
    const Configured = @TypeOf(program.handlers(.{
        handleTransform(ping, no_state{}, struct {
            /// Supply the transform witness value.
            pub fn resumeValue(_: no_state, _: void) i32 {
                return 0;
            }
            /// Preserve the resumed answer unchanged.
            pub fn afterResume(_: no_state, answer: i32) i32 {
                return answer;
            }
        }),
    }));
    const context_info = @typeInfo(Configured.Context).@"struct";
    const BindingsPtrType = context_info.fields[0].type;
    const BindingsType = @typeInfo(BindingsPtrType).pointer.child;
    const FirstFieldType = @typeInfo(BindingsType).@"struct".fields[0].type;

    try std.testing.expect(@typeInfo(FirstFieldType) != .optional);
}

test "binding payload storage stays pointer-based" {
    const ping = TransformOp("ping", usize, usize);
    const no_state = struct {};
    const spec = handleTransform(ping, no_state{}, struct {
        /// Supply the transform witness value.
        pub fn resumeValue(_: no_state, payload: usize) usize {
            return payload;
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: usize) usize {
            return answer;
        }
    });
    const BindingType = Binding(@TypeOf(spec), usize, usize, error{});

    try std.testing.expectEqual(ping.Payload, @FieldType(BindingType.HandlerCarrier(), "payload"));
}

test "transform program resumes and observes final answer" {
    const NoError = error{};
    const add = TransformOp("add", i32, i32);
    const demo = Program(i32, i32, NoError, .{add});
    const no_state = struct {};
    const transform_handler = struct {
        /// Supply the resumptive transform value.
        pub fn resumeValue(_: no_state, payload: i32) i32 {
            return payload + 40;
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    };
    const configured = demo.handlers(.{
        handleTransform(add, no_state{}, transform_handler),
    });

    const body = struct {
        /// Run the transform witness body through the explicit program path.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(add, 1, struct {
            /// Increment the transform resume value.
            pub fn apply(value: i32) i32 {
                return value + 1;
            }
        })) {
            return ctx.performProgram(add, 1, struct {
                /// Increment the transform resume value.
                pub fn apply(value: i32) i32 {
                    return value + 1;
                }
            });
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try configured.run(&runtime, body);
    try std.testing.expectEqual(@as(i32, 42), result);
}

test "const authored transform programs stay activatable" {
    const NoError = error{};
    const add = TransformOp("const_authored_add", i32, i32);
    const demo = Program(i32, i32, NoError, .{add});
    const no_state = struct {};
    const transform_handler = struct {
        /// Return the resumed value for the const-authored transform regression.
        pub fn resumeValue(_: no_state, payload: i32) i32 {
            return payload + 40;
        }

        /// Preserve the resumed answer so the test isolates authored activation behavior.
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    };
    const configured = demo.handlers(.{
        handleTransform(add, no_state{}, transform_handler),
    });

    const body = struct {
        /// Return one const-authored transform program and exercise const-safe activation calls.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(add, 1, struct {
            /// Increment the resumed transform value.
            pub fn apply(value: i32) i32 {
                return value + 1;
            }
        })) {
            const authored = ctx.performProgram(add, 1, struct {
                /// Increment the resumed transform value through the returned authored program.
                pub fn apply(value: i32) i32 {
                    return value + 1;
                }
            });
            authored.activate();
            authored.deactivate();
            return authored;
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try configured.run(&runtime, body);
    try std.testing.expectEqual(@as(i32, 42), result);
}

test "choice program may return now" {
    const NoError = error{};
    const pick = ChoiceOp("pick", i32, i32);
    const demo = Program([]const u8, []const u8, NoError, .{pick});
    const no_state = struct {};
    const choice_handler = struct {
        /// Return immediately from the choice witness.
        pub fn resumeOrReturn(_: no_state, _: i32) prompt_contract.ResumeOrReturn(i32, []const u8) {
            return prompt_contract.ResumeOrReturn(i32, []const u8).returnNow("early");
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: []const u8) []const u8 {
            return answer;
        }
    };
    const configured = demo.handlers(.{
        handleChoice(pick, no_state{}, choice_handler),
    });

    const body = struct {
        /// Run the choice witness body through the explicit program path.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(pick, 0, struct {
            /// Produce the late answer if the choice resumes.
            pub fn apply(_: i32) []const u8 {
                return "late";
            }
        })) {
            return ctx.performProgram(pick, 0, struct {
                /// Produce the late answer if the choice resumes.
                pub fn apply(_: i32) []const u8 {
                    return "late";
                }
            });
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try configured.run(&runtime, body);
    try std.testing.expectEqualStrings("early", result);
}

test "const authored choice programs with context stay activatable" {
    const NoError = error{};
    const pick = ChoiceOp("const_authored_pick", i32, i32);
    const demo = Program([]const u8, []const u8, NoError, .{pick});
    const no_state = struct {};
    const choice_handler = struct {
        /// Return early so the const-authored choice test can verify activation without resuming.
        pub fn resumeOrReturn(_: no_state, _: i32) prompt_contract.ResumeOrReturn(i32, []const u8) {
            return prompt_contract.ResumeOrReturn(i32, []const u8).returnNow("early");
        }

        /// Preserve the resumed answer when the continuation is taken.
        pub fn afterResume(_: no_state, answer: []const u8) []const u8 {
            return answer;
        }
    };
    const configured = demo.handlers(.{
        handleChoice(pick, no_state{}, choice_handler),
    });
    const ContextType = @TypeOf(configured).Context;
    const BindingsType = std.meta.Child(@FieldType(ContextType, "bindings"));
    const ContinuationState = struct {
        resumed: bool = false,

        /// Mark whether the continuation resumed unexpectedly.
        pub fn apply(state: *@This(), _: i32) []const u8 {
            state.resumed = true;
            return "late";
        }
    };

    var bindings = BindingsType.init(configured.specs);
    var ctx = ContextType{ .bindings = &bindings };
    var continuation_state = ContinuationState{};
    const authored = ctx.performProgramWithContext(pick, 0, &continuation_state, ContinuationState);
    authored.activate();
    defer authored.deactivate();

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try frontend.run(&runtime, authored.prompt, authored.program);
    try std.testing.expectEqualStrings("early", result);
    try std.testing.expect(!continuation_state.resumed);
}

test "abort program never resumes body tail" {
    const NoError = error{};
    const fail = AbortOp("fail", []const u8);
    const demo = Program([]const u8, []const u8, NoError, .{fail});
    const no_state = struct {};
    const abort_handler = struct {
        /// Return the abort payload unchanged.
        pub fn directReturn(_: no_state, payload: []const u8) []const u8 {
            return payload;
        }
    };
    const configured = demo.handlers(.{
        handleAbort(fail, no_state{}, abort_handler),
    });

    const body = struct {
        var after_abort = false;

        /// Run the abort witness body through the explicit program path.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(fail, "abort", struct {
            /// Mark that the abort continuation resumed unexpectedly.
            pub fn apply(_: noreturn) []const u8 {
                after_abort = true;
                return "late";
            }
        })) {
            return ctx.performProgram(fail, "abort", struct {
                /// Mark that the abort continuation resumed unexpectedly.
                pub fn apply(_: noreturn) []const u8 {
                    after_abort = true;
                    return "late";
                }
            });
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    body.after_abort = false;
    const result = try configured.run(&runtime, body);
    try std.testing.expectEqualStrings("abort", result);
    try std.testing.expect(!body.after_abort);
}

test "warmed algebraic perform path adds no allocator traffic" {
    const CountingAllocator = struct {
        child: std.mem.Allocator,
        alloc_calls: usize = 0,
        resize_calls: usize = 0,
        remap_calls: usize = 0,
        free_calls: usize = 0,

        fn init(child: std.mem.Allocator) @This() {
            return .{ .child = child };
        }

        fn allocator(self: *@This()) std.mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .remap = remap,
                    .free = free,
                },
            };
        }

        fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.alloc_calls += 1;
            return self.child.rawAlloc(len, alignment, ret_addr);
        }

        fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.resize_calls += 1;
            return self.child.rawResize(memory, alignment, new_len, ret_addr);
        }

        fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.remap_calls += 1;
            return self.child.rawRemap(memory, alignment, new_len, ret_addr);
        }

        fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.free_calls += 1;
            self.child.rawFree(memory, alignment, ret_addr);
        }
    };

    const NoError = error{};
    const add = TransformOp("warm_add", i32, i32);
    const demo = Program(i32, i32, NoError, .{add});
    const no_state = struct {};
    const add_handler = struct {
        /// Supply the warmed transform value.
        pub fn resumeValue(_: no_state, payload: i32) i32 {
            return payload + 1;
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    };
    const configured = demo.handlers(.{
        handleTransform(add, no_state{}, add_handler),
    });

    const body = struct {
        /// Run the warmed no-allocation witness body through the explicit program path.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(add, 41, struct {
            /// Preserve the warmed transform answer unchanged.
            pub fn apply(value: i32) i32 {
                return value;
            }
        })) {
            return ctx.performProgram(add, 41, struct {
                /// Preserve the warmed transform answer unchanged.
                pub fn apply(value: i32) i32 {
                    return value;
                }
            });
        }
    };

    var counting = CountingAllocator.init(std.testing.allocator);
    var runtime = lowered_machine.Runtime.init(counting.allocator());
    defer runtime.deinit();

    const warm = try configured.run(&runtime, body);
    try std.testing.expectEqual(@as(i32, 42), warm);

    const alloc_calls = counting.alloc_calls;
    const resize_calls = counting.resize_calls;
    const remap_calls = counting.remap_calls;
    const free_calls = counting.free_calls;

    const second = try configured.run(&runtime, body);
    try std.testing.expectEqual(@as(i32, 42), second);
    try std.testing.expectEqual(alloc_calls, counting.alloc_calls);
    try std.testing.expectEqual(resize_calls, counting.resize_calls);
    try std.testing.expectEqual(remap_calls, counting.remap_calls);
    try std.testing.expectEqual(free_calls, counting.free_calls);
}
