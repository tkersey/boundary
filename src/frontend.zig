const lowered_machine = @import("lowered_machine");
const portable_core = @import("portable_core");
const prompt_contract = @import("prompt_contract_support");
const std = @import("std");

const EncodedValue = lowered_machine.ProgramValue;

const FrameBase = struct {
    prompt_token: prompt_contract.PromptToken,
    prompt_identity: *const anyopaque,
    runtime_previous_for_token: ?*FrameBase = null,
    compat_previous_for_token: ?*FrameBase = null,
};

fn PromptTypeFromPtr(comptime PromptPtrType: type) type {
    return switch (@typeInfo(PromptPtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to ability.Prompt(...)"),
    };
}

fn PromptOutAnswerType(comptime PromptPtrType: type) type {
    return PromptTypeFromPtr(PromptPtrType).OutAnswer;
}

fn PromptErrorSetType(comptime PromptPtrType: type) type {
    return PromptTypeFromPtr(PromptPtrType).ErrorSet;
}

fn assertPromptMode(comptime PromptPtrType: type, comptime expected: prompt_contract.PromptMode, comptime operation: []const u8) void {
    if (PromptTypeFromPtr(PromptPtrType).mode != expected) {
        @compileError("frontend." ++ operation ++ " requires a prompt with matching mode");
    }
}

fn assertPromptTypeMode(comptime PromptType: type, comptime expected: prompt_contract.PromptMode, comptime operation: []const u8) void {
    if (PromptType.mode != expected) {
        @compileError("frontend." ++ operation ++ " requires a prompt with matching mode");
    }
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

fn ContinuationFnType(comptime Continuation: anytype) type {
    const Carrier = ContinuationCarrierType(Continuation);
    if (continuationHasApply(Continuation)) return @TypeOf(Continuation.apply);
    return switch (@typeInfo(Carrier)) {
        .@"fn" => Carrier,
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn")
            pointer.child
        else
            @compileError(@typeName(Carrier) ++ " must declare apply or be a callable function"),
        else => @compileError(@typeName(Carrier) ++ " must declare apply or be a callable function"),
    };
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

fn ResumeOrReturnType(comptime Resume: type, comptime PromptType: type) type {
    return prompt_contract.ResumeOrReturn(Resume, PromptType.OutAnswer);
}

fn assertHandlerProtocol(comptime Resume: type, comptime PromptType: type, comptime Handler: type) void {
    switch (PromptType.mode) {
        .resume_or_return => {
            if (!hasDeclSafe(Handler, "resumeOrReturn")) @compileError(@typeName(Handler) ++ " must declare resumeOrReturn");
            if (!fnParamsMatch(@TypeOf(Handler.resumeOrReturn), &.{}) or !fnReturnMatches(@TypeOf(Handler.resumeOrReturn), ResumeOrReturnType(Resume, PromptType))) {
                @compileError(@typeName(Handler) ++ ".resumeOrReturn must have type fn () ResumeOrReturn or fn () ResetError(ErrorSet)!ResumeOrReturn");
            }
            if (!hasDeclSafe(Handler, "afterResume")) @compileError(@typeName(Handler) ++ " must declare afterResume");
            if (!fnParamsMatch(@TypeOf(Handler.afterResume), &.{PromptType.InAnswer}) or !fnReturnMatches(@TypeOf(Handler.afterResume), PromptType.OutAnswer)) {
                @compileError(@typeName(Handler) ++ ".afterResume must have type fn (InAnswer) OutAnswer or fn (InAnswer) ResetError(ErrorSet)!OutAnswer");
            }
        },
        .resume_then_transform => {
            if (!hasDeclSafe(Handler, "resumeValue")) @compileError(@typeName(Handler) ++ " must declare resumeValue");
            if (!fnParamsMatch(@TypeOf(Handler.resumeValue), &.{}) or !fnReturnMatches(@TypeOf(Handler.resumeValue), Resume)) {
                @compileError(@typeName(Handler) ++ ".resumeValue must have type fn () Resume or fn () ResetError(ErrorSet)!Resume");
            }
            if (!hasDeclSafe(Handler, "afterResume")) @compileError(@typeName(Handler) ++ " must declare afterResume");
            if (!fnParamsMatch(@TypeOf(Handler.afterResume), &.{PromptType.InAnswer}) or !fnReturnMatches(@TypeOf(Handler.afterResume), PromptType.OutAnswer)) {
                @compileError(@typeName(Handler) ++ ".afterResume must have type fn (InAnswer) OutAnswer or fn (InAnswer) ResetError(ErrorSet)!OutAnswer");
            }
        },
        .direct_return => {
            if (!hasDeclSafe(Handler, "directReturn")) @compileError(@typeName(Handler) ++ " must declare directReturn");
            if (!fnParamsMatch(@TypeOf(Handler.directReturn), &.{}) or !fnReturnMatches(@TypeOf(Handler.directReturn), PromptType.OutAnswer)) {
                @compileError(@typeName(Handler) ++ ".directReturn must have type fn () OutAnswer or fn () ResetError(ErrorSet)!OutAnswer");
            }
        },
    }
}

fn callResumeValue(comptime Resume: type, comptime PromptType: type, comptime Handler: type) lowered_machine.ControlError(PromptType.ErrorSet)!Resume {
    const ResumeFn = @TypeOf(Handler.resumeValue);
    if (ResumeFn == fn () Resume) return Handler.resumeValue();
    return Handler.resumeValue() catch |err| return @errorCast(err);
}

fn callAfterResume(
    comptime PromptType: type,
    comptime Handler: type,
    value: PromptType.InAnswer,
) lowered_machine.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer {
    const AfterFn = @TypeOf(Handler.afterResume);
    if (AfterFn == fn (PromptType.InAnswer) PromptType.OutAnswer) return Handler.afterResume(value);
    return Handler.afterResume(value) catch |err| return @errorCast(err);
}

fn callDirectReturn(comptime PromptType: type, comptime Handler: type) lowered_machine.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer {
    const DirectFn = @TypeOf(Handler.directReturn);
    if (DirectFn == fn () PromptType.OutAnswer) return Handler.directReturn();
    return Handler.directReturn() catch |err| return @errorCast(err);
}

fn callResumeOrReturn(comptime Resume: type, comptime PromptType: type, comptime Handler: type) lowered_machine.ControlError(PromptType.ErrorSet)!ResumeOrReturnType(Resume, PromptType) {
    const ResumeOrReturnFn = @TypeOf(Handler.resumeOrReturn);
    if (ResumeOrReturnFn == fn () ResumeOrReturnType(Resume, PromptType)) return Handler.resumeOrReturn();
    return Handler.resumeOrReturn() catch |err| return @errorCast(err);
}

fn assertHandlerProtocolWithContext(
    comptime Resume: type,
    comptime PromptType: type,
    comptime ContextPtrType: type,
    comptime Handler: type,
) void {
    switch (PromptType.mode) {
        .resume_or_return => {
            if (!hasDeclSafe(Handler, "resumeOrReturn")) @compileError(@typeName(Handler) ++ " must declare resumeOrReturn");
            if (!fnParamsMatch(@TypeOf(Handler.resumeOrReturn), &.{ContextPtrType}) or !fnReturnMatches(@TypeOf(Handler.resumeOrReturn), ResumeOrReturnType(Resume, PromptType))) {
                @compileError(@typeName(Handler) ++ ".resumeOrReturn must have type fn (Ctx) ResumeOrReturn or fn (Ctx) ResetError(ErrorSet)!ResumeOrReturn");
            }
            if (!hasDeclSafe(Handler, "afterResume")) @compileError(@typeName(Handler) ++ " must declare afterResume");
            if (!fnParamsMatch(@TypeOf(Handler.afterResume), &.{ ContextPtrType, PromptType.InAnswer }) or !fnReturnMatches(@TypeOf(Handler.afterResume), PromptType.OutAnswer)) {
                @compileError(@typeName(Handler) ++ ".afterResume must have type fn (Ctx, InAnswer) OutAnswer or fn (Ctx, InAnswer) ResetError(ErrorSet)!OutAnswer");
            }
        },
        .resume_then_transform => {
            if (!hasDeclSafe(Handler, "resumeValue")) @compileError(@typeName(Handler) ++ " must declare resumeValue");
            if (!fnParamsMatch(@TypeOf(Handler.resumeValue), &.{ContextPtrType}) or !fnReturnMatches(@TypeOf(Handler.resumeValue), Resume)) {
                @compileError(@typeName(Handler) ++ ".resumeValue must have type fn (Ctx) Resume or fn (Ctx) ResetError(ErrorSet)!Resume");
            }
            if (!hasDeclSafe(Handler, "afterResume")) @compileError(@typeName(Handler) ++ " must declare afterResume");
            if (!fnParamsMatch(@TypeOf(Handler.afterResume), &.{ ContextPtrType, PromptType.InAnswer }) or !fnReturnMatches(@TypeOf(Handler.afterResume), PromptType.OutAnswer)) {
                @compileError(@typeName(Handler) ++ ".afterResume must have type fn (Ctx, InAnswer) OutAnswer or fn (Ctx, InAnswer) ResetError(ErrorSet)!OutAnswer");
            }
        },
        .direct_return => {
            if (!hasDeclSafe(Handler, "directReturn")) @compileError(@typeName(Handler) ++ " must declare directReturn");
            if (!fnParamsMatch(@TypeOf(Handler.directReturn), &.{ContextPtrType}) or !fnReturnMatches(@TypeOf(Handler.directReturn), PromptType.OutAnswer)) {
                @compileError(@typeName(Handler) ++ ".directReturn must have type fn (Ctx) OutAnswer or fn (Ctx) ResetError(ErrorSet)!OutAnswer");
            }
        },
    }
}

fn assertAfterResumeProtocolWithContext(
    comptime PromptType: type,
    comptime ContextPtrType: type,
    comptime Handler: type,
) void {
    if (!hasDeclSafe(Handler, "afterResume")) @compileError(@typeName(Handler) ++ " must declare afterResume");
    if (!fnParamsMatch(@TypeOf(Handler.afterResume), &.{ ContextPtrType, PromptType.InAnswer }) or !fnReturnMatches(@TypeOf(Handler.afterResume), PromptType.OutAnswer)) {
        @compileError(@typeName(Handler) ++ ".afterResume must have type fn (Ctx, InAnswer) OutAnswer or fn (Ctx, InAnswer) ResetError(ErrorSet)!OutAnswer");
    }
}

fn callResumeValueWithContext(
    comptime Resume: type,
    comptime PromptType: type,
    comptime ContextPtrType: type,
    comptime Handler: type,
    ctx: ContextPtrType,
) lowered_machine.ControlError(PromptType.ErrorSet)!Resume {
    const ResumeFn = @TypeOf(Handler.resumeValue);
    if (ResumeFn == fn (ContextPtrType) Resume) return Handler.resumeValue(ctx);
    return Handler.resumeValue(ctx) catch |err| return @errorCast(err);
}

fn callAfterResumeWithContext(
    comptime PromptType: type,
    comptime ContextPtrType: type,
    comptime Handler: type,
    ctx: ContextPtrType,
    value: PromptType.InAnswer,
) lowered_machine.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer {
    const AfterFn = @TypeOf(Handler.afterResume);
    if (AfterFn == fn (ContextPtrType, PromptType.InAnswer) PromptType.OutAnswer) return Handler.afterResume(ctx, value);
    return Handler.afterResume(ctx, value) catch |err| return @errorCast(err);
}

fn callDirectReturnWithContext(
    comptime PromptType: type,
    comptime ContextPtrType: type,
    comptime Handler: type,
    ctx: ContextPtrType,
) lowered_machine.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer {
    const DirectFn = @TypeOf(Handler.directReturn);
    if (DirectFn == fn (ContextPtrType) PromptType.OutAnswer) return Handler.directReturn(ctx);
    return Handler.directReturn(ctx) catch |err| return @errorCast(err);
}

fn callResumeOrReturnWithContext(
    comptime Resume: type,
    comptime PromptType: type,
    comptime ContextPtrType: type,
    comptime Handler: type,
    ctx: ContextPtrType,
) lowered_machine.ControlError(PromptType.ErrorSet)!ResumeOrReturnType(Resume, PromptType) {
    const ResumeOrReturnFn = @TypeOf(Handler.resumeOrReturn);
    if (ResumeOrReturnFn == fn (ContextPtrType) ResumeOrReturnType(Resume, PromptType)) return Handler.resumeOrReturn(ctx);
    return Handler.resumeOrReturn(ctx) catch |err| return @errorCast(err);
}

fn assertBorrowedContextPtrType(comptime ContextPtrType: type, comptime label: []const u8) void {
    const pointer_info = @typeInfo(ContextPtrType).pointer;
    if (@typeInfo(ContextPtrType) != .pointer or pointer_info.size != .one) {
        @compileError("frontend." ++ label ++ " currently requires a single-item pointer handler context");
    }
}

fn assertContinuationType(
    comptime Input: type,
    comptime PromptType: type,
    comptime Continuation: anytype,
) void {
    const FnType = ContinuationFnType(Continuation);
    if (!fnParamsMatch(FnType, &.{Input}) or !fnReturnMatches(FnType, PromptType.InAnswer)) {
        @compileError(@typeName(ContinuationCarrierType(Continuation)) ++ " must have type fn (Input) InAnswer or fn (Input) ResetError(ErrorSet)!InAnswer");
    }
}

fn callContinuation(
    comptime Input: type,
    comptime PromptType: type,
    comptime Continuation: anytype,
    value: Input,
) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
    if (comptime continuationHasApply(Continuation)) {
        const ApplyFn = @TypeOf(Continuation.apply);
        if (ApplyFn == fn (Input) PromptType.InAnswer) return Continuation.apply(value);
        return Continuation.apply(value) catch |err| return @errorCast(err);
    }
    if (comptime @TypeOf(Continuation) == type) {
        @compileError("frontend explicit continuations must be passed as callable values, not function types");
    }
    const FnType = ContinuationFnType(Continuation);
    if (FnType == fn (Input) PromptType.InAnswer) return Continuation(value);
    return Continuation(value) catch |err| return @errorCast(err);
}

fn encodeValue(comptime T: type, value: T) lowered_machine.Error!EncodedValue {
    if (T == void) {
        return .none;
    }
    if (T == bool) return .{ .bool = value };
    if (T == i32) return .{ .i32 = value };
    if (T == []const u8) return .{ .string = value };
    if (T == usize) return .{ .usize = value };
    @compileError("frontend explicit programs currently support only void, bool, i32, usize, and []const u8 values");
}

fn decodeValue(comptime T: type, value: EncodedValue) T {
    if (T == void) return;
    if (T == bool) return switch (value) {
        .bool => |typed| typed,
        else => unreachable,
    };
    if (T == i32) return switch (value) {
        .i32 => |typed| typed,
        else => unreachable,
    };
    if (T == usize) return switch (value) {
        .usize => |typed| typed,
        else => unreachable,
    };
    if (T == []const u8) return switch (value) {
        .string => |typed| typed,
        else => unreachable,
    };
    @compileError("frontend explicit programs currently support only void, bool, i32, usize, and []const u8 values");
}

fn DecisionValue(comptime PromptType: type) type {
    return union(enum) {
        resume_with: EncodedValue,
        return_now: PromptType.OutAnswer,
    };
}

/// Typed authored body for one canonical prompt.
pub fn Program(comptime PromptType: type) type {
    return union(enum) {
        abort: struct {
            handler_ctx: ?*anyopaque,
            directReturnFn: *const fn (?*anyopaque) lowered_machine.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer,
        },
        choice: struct {
            handler_ctx: ?*anyopaque,
            decisionFn: *const fn (?*anyopaque) lowered_machine.ControlError(PromptType.ErrorSet)!DecisionValue(PromptType),
            continue_ctx: ?*anyopaque,
            continueFn: *const fn (?*anyopaque, EncodedValue) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer,
            afterResumeFn: AfterResumeFn(PromptType),
        },
        compute: struct {
            ctx: ?*anyopaque,
            invokeFn: *const fn (?*anyopaque) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer,
        },
        pure: PromptType.InAnswer,
        transform: struct {
            handler_ctx: ?*anyopaque,
            resumeValueFn: *const fn (?*anyopaque) lowered_machine.ControlError(PromptType.ErrorSet)!EncodedValue,
            continueFn: *const fn (EncodedValue) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer,
            afterResumeFn: AfterResumeFn(PromptType),
        },
    };
}

/// One explicit program paired with the concrete prompt value it must run under.
pub fn BoundProgram(comptime PromptType: type) type {
    return struct {
        prompt: *const PromptType,
        program: Program(PromptType),
        activateFn: ?*const fn () void = null,
        deactivateFn: ?*const fn () void = null,

        /// Activate any runtime-local binding state before execution begins.
        pub fn activate(self: @This()) void {
            if (self.activateFn) |f| f();
        }

        /// Restore runtime-local binding state after execution completes.
        pub fn deactivate(self: @This()) void {
            if (self.deactivateFn) |f| f();
        }
    };
}

/// Build one explicit canonical program from a body spec type.
pub fn build(
    comptime PromptType: type,
    comptime Spec: type,
) Program(PromptType) {
    if (!hasDeclSafe(Spec, "program")) {
        @compileError("frontend.build requires Spec.program");
    }
    const ProgramFn = @TypeOf(Spec.program);
    if (ProgramFn != fn () Program(PromptType)) {
        @compileError("Spec.program must have type fn () frontend.Program(PromptType)");
    }
    return Spec.program();
}

/// Build a pure explicit program for prompts whose body answer is already final.
pub fn pureProgram(comptime PromptType: type, value: PromptType.InAnswer) Program(PromptType) {
    return .{ .pure = value };
}

/// Build an explicit non-replay leaf program that executes one computation exactly once.
pub fn computeProgram(
    comptime PromptType: type,
    thunk: anytype,
) Program(PromptType) {
    return .{
        .compute = .{
            .ctx = null,
            .invokeFn = struct {
                fn invoke(_: ?*anyopaque) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
                    return try normalizeBodyFn(PromptType, thunk)();
                }
            }.invoke,
        },
    };
}

/// Build an explicit compute program whose thunk receives one explicit context pointer.
pub fn computeProgramWithContext(
    comptime PromptType: type,
    ctx: anytype,
    thunk: anytype,
) Program(PromptType) {
    const ContextPtrType = @TypeOf(ctx);
    return .{
        .compute = .{
            .ctx = @ptrCast(ctx),
            .invokeFn = struct {
                fn invoke(raw_ctx: ?*anyopaque) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
                    const typed_ctx: ContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    return try thunk(typed_ctx);
                }
            }.invoke,
        },
    };
}

/// Build one explicit transform program with a single resumptive operation.
pub fn transformProgram(
    comptime PromptType: type,
    comptime Resume: type,
    comptime Handler: type,
    comptime Continuation: anytype,
) Program(PromptType) {
    comptime assertPromptTypeMode(PromptType, .resume_then_transform, "transformProgram");
    comptime assertHandlerProtocol(Resume, PromptType, Handler);
    comptime assertContinuationType(Resume, PromptType, Continuation);
    return .{
        .transform = .{
            .handler_ctx = null,
            .resumeValueFn = struct {
                fn invoke(_: ?*anyopaque) lowered_machine.ControlError(PromptType.ErrorSet)!EncodedValue {
                    return try encodeValue(Resume, try callResumeValue(Resume, PromptType, Handler));
                }
            }.invoke,
            .continueFn = struct {
                fn invoke(value: EncodedValue) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
                    return try callContinuation(Resume, PromptType, Continuation, decodeValue(Resume, value));
                }
            }.invoke,
            .afterResumeFn = afterResumeThunk(PromptType, Handler),
        },
    };
}

/// Build one explicit transform program whose handler receives one explicit runtime context pointer.
pub fn transformProgramWithContext(
    comptime PromptType: type,
    comptime Resume: type,
    handler_ctx: anytype,
    comptime Handler: type,
    comptime Continuation: anytype,
) Program(PromptType) {
    const ContextPtrType = @TypeOf(handler_ctx);
    comptime assertPromptTypeMode(PromptType, .resume_then_transform, "transformProgramWithContext");
    comptime assertHandlerProtocolWithContext(Resume, PromptType, ContextPtrType, Handler);
    comptime assertContinuationType(Resume, PromptType, Continuation);
    return .{
        .transform = .{
            .handler_ctx = @ptrCast(@constCast(handler_ctx)),
            .resumeValueFn = struct {
                fn invoke(raw_ctx: ?*anyopaque) lowered_machine.ControlError(PromptType.ErrorSet)!EncodedValue {
                    const typed_ctx: ContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    return try encodeValue(Resume, try callResumeValueWithContext(Resume, PromptType, ContextPtrType, Handler, typed_ctx));
                }
            }.invoke,
            .continueFn = struct {
                fn invoke(value: EncodedValue) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
                    return try callContinuation(Resume, PromptType, Continuation, decodeValue(Resume, value));
                }
            }.invoke,
            .afterResumeFn = struct {
                fn invoke(raw_ctx: ?*anyopaque, value: PromptType.InAnswer) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
                    const typed_ctx: ContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    return try callAfterResumeWithContext(PromptType, ContextPtrType, Handler, typed_ctx, value);
                }
            }.invoke,
        },
    };
}

/// Build one explicit choice program whose continuation receives one explicit runtime context pointer.
pub fn choiceProgramWithContext(
    comptime PromptType: type,
    comptime Resume: type,
    comptime Handler: type,
    continuation_ctx: anytype,
    comptime Continuation: type,
) Program(PromptType) {
    const ContextPtrType = @TypeOf(continuation_ctx);
    const ContextFn = @TypeOf(Continuation.apply);
    comptime assertPromptTypeMode(PromptType, .resume_or_return, "choiceProgramWithContext");
    comptime assertHandlerProtocol(Resume, PromptType, Handler);
    comptime {
        if (!@hasDecl(Continuation, "apply")) @compileError("contextual lexical choice continuation must declare apply(ctx, value)");
        if (!fnParamsMatch(ContextFn, &.{ ContextPtrType, Resume }) or !fnReturnMatches(ContextFn, PromptType.InAnswer)) {
            @compileError("contextual lexical choice continuation apply must have type fn (Ctx, Resume) InAnswer or fn (Ctx, Resume) ResetError(ErrorSet)!InAnswer");
        }
    }
    return .{
        .choice = .{
            .handler_ctx = null,
            .decisionFn = struct {
                fn invoke(_: ?*anyopaque) lowered_machine.ControlError(PromptType.ErrorSet)!DecisionValue(PromptType) {
                    const decision = try callResumeOrReturn(Resume, PromptType, Handler);
                    return switch (decision) {
                        .resume_with => |value| .{ .resume_with = try encodeValue(Resume, value) },
                        .return_now => |answer| .{ .return_now = answer },
                    };
                }
            }.invoke,
            .continue_ctx = @ptrCast(continuation_ctx),
            .continueFn = struct {
                fn invoke(raw_ctx: ?*anyopaque, value: EncodedValue) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
                    const typed_ctx: ContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    const ReturnType = @TypeOf(Continuation.apply(typed_ctx, decodeValue(Resume, value)));
                    if (@typeInfo(ReturnType) == .error_union) {
                        return Continuation.apply(typed_ctx, decodeValue(Resume, value)) catch |err| return @errorCast(err);
                    }
                    return Continuation.apply(typed_ctx, decodeValue(Resume, value));
                }
            }.invoke,
            .afterResumeFn = afterResumeThunk(PromptType, Handler),
        },
    };
}

/// Build one explicit choice program whose handler receives one explicit runtime context pointer.
pub fn choiceProgramWithHandlerContext(
    comptime PromptType: type,
    comptime Resume: type,
    handler_ctx: anytype,
    comptime Handler: type,
    comptime Continuation: anytype,
) Program(PromptType) {
    const ContextPtrType = @TypeOf(handler_ctx);
    comptime assertPromptTypeMode(PromptType, .resume_or_return, "choiceProgramWithHandlerContext");
    comptime assertHandlerProtocolWithContext(Resume, PromptType, ContextPtrType, Handler);
    comptime assertContinuationType(Resume, PromptType, Continuation);
    return .{
        .choice = .{
            .handler_ctx = @ptrCast(@constCast(handler_ctx)),
            .decisionFn = struct {
                fn invoke(raw_ctx: ?*anyopaque) lowered_machine.ControlError(PromptType.ErrorSet)!DecisionValue(PromptType) {
                    const typed_ctx: ContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    const decision = try callResumeOrReturnWithContext(Resume, PromptType, ContextPtrType, Handler, typed_ctx);
                    return switch (decision) {
                        .resume_with => |value| .{ .resume_with = try encodeValue(Resume, value) },
                        .return_now => |answer| .{ .return_now = answer },
                    };
                }
            }.invoke,
            .continue_ctx = null,
            .continueFn = struct {
                fn invoke(_: ?*anyopaque, value: EncodedValue) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
                    return try callContinuation(Resume, PromptType, Continuation, decodeValue(Resume, value));
                }
            }.invoke,
            .afterResumeFn = struct {
                fn invoke(raw_ctx: ?*anyopaque, value: PromptType.InAnswer) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
                    const typed_ctx: ContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    return try callAfterResumeWithContext(PromptType, ContextPtrType, Handler, typed_ctx, value);
                }
            }.invoke,
        },
    };
}

/// Build one explicit choice program whose handler and continuation each receive explicit runtime context pointers.
pub fn choiceProgramWithContexts(
    comptime PromptType: type,
    comptime Resume: type,
    handler_ctx: anytype,
    comptime Handler: type,
    continuation_ctx: anytype,
    comptime Continuation: type,
) Program(PromptType) {
    const HandlerContextPtrType = @TypeOf(handler_ctx);
    const ContinuationContextPtrType = @TypeOf(continuation_ctx);
    const ContextFn = @TypeOf(Continuation.apply);
    comptime assertPromptTypeMode(PromptType, .resume_or_return, "choiceProgramWithContexts");
    comptime assertHandlerProtocolWithContext(Resume, PromptType, HandlerContextPtrType, Handler);
    comptime {
        if (!@hasDecl(Continuation, "apply")) @compileError("contextual lexical choice continuation must declare apply(ctx, value)");
        if (!fnParamsMatch(ContextFn, &.{ ContinuationContextPtrType, Resume }) or !fnReturnMatches(ContextFn, PromptType.InAnswer)) {
            @compileError("contextual lexical choice continuation apply must have type fn (Ctx, Resume) InAnswer or fn (Ctx, Resume) ResetError(ErrorSet)!InAnswer");
        }
    }
    return .{
        .choice = .{
            .handler_ctx = @ptrCast(@constCast(handler_ctx)),
            .decisionFn = struct {
                fn invoke(raw_ctx: ?*anyopaque) lowered_machine.ControlError(PromptType.ErrorSet)!DecisionValue(PromptType) {
                    const typed_ctx: HandlerContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    const decision = try callResumeOrReturnWithContext(Resume, PromptType, HandlerContextPtrType, Handler, typed_ctx);
                    return switch (decision) {
                        .resume_with => |value| .{ .resume_with = try encodeValue(Resume, value) },
                        .return_now => |answer| .{ .return_now = answer },
                    };
                }
            }.invoke,
            .continue_ctx = @ptrCast(continuation_ctx),
            .continueFn = struct {
                fn invoke(raw_ctx: ?*anyopaque, value: EncodedValue) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
                    const typed_ctx: ContinuationContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    const ReturnType = @TypeOf(Continuation.apply(typed_ctx, decodeValue(Resume, value)));
                    if (@typeInfo(ReturnType) == .error_union) {
                        return Continuation.apply(typed_ctx, decodeValue(Resume, value)) catch |err| return @errorCast(err);
                    }
                    return Continuation.apply(typed_ctx, decodeValue(Resume, value));
                }
            }.invoke,
            .afterResumeFn = struct {
                fn invoke(raw_ctx: ?*anyopaque, value: PromptType.InAnswer) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
                    const typed_ctx: HandlerContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    return try callAfterResumeWithContext(PromptType, HandlerContextPtrType, Handler, typed_ctx, value);
                }
            }.invoke,
        },
    };
}

/// Build one explicit choice program with a single zero-or-one-resume operation.
pub fn choiceProgram(
    comptime PromptType: type,
    comptime Resume: type,
    comptime Handler: type,
    comptime Continuation: anytype,
) Program(PromptType) {
    comptime assertPromptTypeMode(PromptType, .resume_or_return, "choiceProgram");
    comptime assertHandlerProtocol(Resume, PromptType, Handler);
    comptime assertContinuationType(Resume, PromptType, Continuation);
    return .{
        .choice = .{
            .handler_ctx = null,
            .decisionFn = struct {
                fn invoke(_: ?*anyopaque) lowered_machine.ControlError(PromptType.ErrorSet)!DecisionValue(PromptType) {
                    const decision = try callResumeOrReturn(Resume, PromptType, Handler);
                    return switch (decision) {
                        .resume_with => |value| .{ .resume_with = try encodeValue(Resume, value) },
                        .return_now => |answer| .{ .return_now = answer },
                    };
                }
            }.invoke,
            .continue_ctx = null,
            .continueFn = struct {
                fn invoke(_: ?*anyopaque, value: EncodedValue) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
                    return try callContinuation(Resume, PromptType, Continuation, decodeValue(Resume, value));
                }
            }.invoke,
            .afterResumeFn = afterResumeThunk(PromptType, Handler),
        },
    };
}

/// Build one explicit abortive program with a single direct-return operation.
pub fn abortProgram(
    comptime PromptType: type,
    comptime Handler: type,
) Program(PromptType) {
    comptime assertPromptTypeMode(PromptType, .direct_return, "abortProgram");
    comptime assertHandlerProtocol(void, PromptType, Handler);
    return .{
        .abort = .{
            .handler_ctx = null,
            .directReturnFn = struct {
                fn invoke(_: ?*anyopaque) lowered_machine.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer {
                    return try callDirectReturn(PromptType, Handler);
                }
            }.invoke,
        },
    };
}

/// Build one explicit abortive program whose handler receives one explicit runtime context pointer.
pub fn abortProgramWithContext(
    comptime PromptType: type,
    handler_ctx: anytype,
    comptime Handler: type,
) Program(PromptType) {
    const ContextPtrType = @TypeOf(handler_ctx);
    comptime assertPromptTypeMode(PromptType, .direct_return, "abortProgramWithContext");
    comptime assertHandlerProtocolWithContext(void, PromptType, ContextPtrType, Handler);
    return .{
        .abort = .{
            .handler_ctx = @ptrCast(@constCast(handler_ctx)),
            .directReturnFn = struct {
                fn invoke(raw_ctx: ?*anyopaque) lowered_machine.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer {
                    const typed_ctx: ContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    return try callDirectReturnWithContext(PromptType, ContextPtrType, Handler, typed_ctx);
                }
            }.invoke,
        },
    };
}

fn normalizeBodyFn(
    comptime PromptType: type,
    body: anytype,
) *const fn () lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
    const InputType = @TypeOf(body);
    const BodyPtrType = *const fn () lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer;
    const BodyFnType = fn () lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer;
    const PureBodyPtrType = *const fn () PromptType.InAnswer;
    const PureBodyFnType = fn () PromptType.InAnswer;

    if (InputType == BodyPtrType) return body;
    if (InputType == BodyFnType) return body;
    if (InputType == PureBodyPtrType or InputType == PureBodyFnType) {
        return struct {
            fn invoke() lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
                return body();
            }
        }.invoke;
    }

    @compileError("expected authored body with type fn () InAnswer or fn () ResetError(ErrorSet)!InAnswer");
}

fn AfterResumeFn(comptime PromptType: type) type {
    return *const fn (?*anyopaque, PromptType.InAnswer) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer;
}

const ContextCleanupFn = *const fn (std.mem.Allocator, ?*anyopaque) void;

fn ResumeRecord(comptime PromptType: type) type {
    return union(enum) {
        resumed: struct {
            storage: []u8,
            after_resume_ctx: ?*anyopaque,
            afterResumeCleanup: ?ContextCleanupFn,
            afterResumeFn: AfterResumeFn(PromptType),
        },
        terminal: PromptType.OutAnswer,
    };
}

fn AppliedAfterRecord(comptime PromptType: type) type {
    return struct {
        ctx: ?*anyopaque,
        afterResumeFn: AfterResumeFn(PromptType),
    };
}

fn Frame(comptime PromptType: type) type {
    return struct {
        base: FrameBase,
        allocator: std.mem.Allocator,
        records: std.ArrayList(ResumeRecord(PromptType)) = .empty,
        applied_after: std.ArrayList(AppliedAfterRecord(PromptType)) = .empty,
        cursor: usize = 0,
        terminal: ?PromptType.OutAnswer = null,

        fn init(allocator: std.mem.Allocator, prompt: *const PromptType) @This() {
            return .{
                .base = .{
                    .prompt_token = prompt.token,
                    .prompt_identity = @ptrCast(prompt),
                },
                .allocator = allocator,
            };
        }

        fn deinit(self: *@This()) void {
            for (self.records.items) |record| switch (record) {
                .resumed => |resumed| {
                    self.allocator.free(resumed.storage);
                    if (resumed.afterResumeCleanup) |cleanup| cleanup(self.allocator, resumed.after_resume_ctx);
                },
                .terminal => {},
            };
            self.records.deinit(self.allocator);
            self.applied_after.deinit(self.allocator);
        }
    };
}

const ReplayCloneState = struct {
    allocator: std.mem.Allocator,
    pointer_clones: std.AutoHashMap(usize, *anyopaque),

    fn init(allocator: std.mem.Allocator) ReplayCloneState {
        return .{
            .allocator = allocator,
            .pointer_clones = std.AutoHashMap(usize, *anyopaque).init(allocator),
        };
    }

    fn deinit(self: *@This()) void {
        self.pointer_clones.deinit();
    }
};

fn PersistedReplayContext(comptime T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        value: T,
    };
}

fn cloneReplayValue(state: *ReplayCloneState, comptime T: type, value: T) lowered_machine.Error!T {
    if (T == std.mem.Allocator) return value;

    return switch (@typeInfo(T)) {
        .void,
        .bool,
        .int,
        .float,
        .comptime_int,
        .comptime_float,
        .null,
        .undefined,
        .noreturn,
        .enum_literal,
        .@"enum",
        .@"fn",
        .error_set,
        .@"opaque",
        .type,
        .vector,
        => value,
        .pointer => |pointer| switch (pointer.size) {
            .one => blk: {
                switch (@typeInfo(pointer.child)) {
                    .@"fn", .@"opaque" => return value,
                    else => {},
                }
                if (state.pointer_clones.get(@intFromPtr(value))) |existing| {
                    break :blk @ptrCast(@alignCast(existing));
                }
                const cloned = state.allocator.create(pointer.child) catch return error.ProgramContractViolation;
                state.pointer_clones.put(@intFromPtr(value), @ptrCast(cloned)) catch return error.ProgramContractViolation;
                cloned.* = try cloneReplayValue(state, pointer.child, value.*);
                break :blk cloned;
            },
            .slice => {
                if (value.len != 0 and @sizeOf(pointer.child) != 0) {
                    const existing_first = state.pointer_clones.get(@intFromPtr(value.ptr));
                    if (existing_first) |first| {
                        const first_clone: [*]pointer.child = @ptrCast(@alignCast(first));
                        var reuses_contiguous_clone = true;
                        for (1..value.len) |index| {
                            const existing_item = state.pointer_clones.get(@intFromPtr(&value[index])) orelse {
                                reuses_contiguous_clone = false;
                                break;
                            };
                            const clone_item: *pointer.child = @ptrCast(@alignCast(existing_item));
                            if (clone_item != &first_clone[index]) {
                                reuses_contiguous_clone = false;
                                break;
                            }
                        }
                        if (reuses_contiguous_clone) return first_clone[0..value.len];
                    }
                }
                const cloned = state.allocator.alloc(pointer.child, value.len) catch return error.ProgramContractViolation;
                for (value, 0..) |item, index| {
                    cloned[index] = try cloneReplayValue(state, pointer.child, item);
                    if (@sizeOf(pointer.child) != 0) {
                        state.pointer_clones.put(@intFromPtr(&value[index]), @ptrCast(&cloned[index])) catch return error.ProgramContractViolation;
                    }
                }
                return cloned;
            },
            .many, .c => @compileError("frontend contextual replay does not support many-pointer or C-pointer handler context fields"),
        },
        .array => |array| {
            var cloned = value;
            for (0..array.len) |index| {
                cloned[index] = try cloneReplayValue(state, array.child, value[index]);
            }
            return cloned;
        },
        .optional => |optional| {
            if (value) |payload| return try cloneReplayValue(state, optional.child, payload);
            return null;
        },
        .@"struct" => |info| {
            var cloned = value;
            inline for (info.fields) |field| {
                @field(cloned, field.name) = try cloneReplayValue(state, field.type, @field(value, field.name));
                if (field.type == std.mem.Allocator) {
                    @field(cloned, field.name) = state.allocator;
                }
            }
            if (@hasField(T, "items") and @hasField(T, "capacity")) {
                const ItemsType = @FieldType(T, "items");
                if (@typeInfo(ItemsType) == .pointer and @typeInfo(ItemsType).pointer.size == .slice and @FieldType(T, "capacity") == usize) {
                    cloned.capacity = cloned.items.len;
                }
            }
            return cloned;
        },
        .@"union" => |union_info| {
            if (union_info.tag_type == null) return value;
            return switch (value) {
                inline else => |payload, tag| @unionInit(T, @tagName(tag), try cloneReplayValue(state, @TypeOf(payload), payload)),
            };
        },
        .error_union => |error_union| {
            if (value) |payload| return try cloneReplayValue(state, error_union.payload, payload);
            return value catch |err| err;
        },
        else => @compileError("frontend contextual replay does not support this handler context field type"),
    };
}

fn persistHandlerContext(
    allocator: std.mem.Allocator,
    comptime ContextPtrType: type,
    handler_ctx: ContextPtrType,
) lowered_machine.Error!struct {
    ctx: ?*anyopaque,
    cleanup: ?ContextCleanupFn,
} {
    const pointer_info = @typeInfo(ContextPtrType).pointer;
    comptime {
        if (@typeInfo(ContextPtrType) != .pointer or pointer_info.size != .one) {
            @compileError("frontend contextual replay currently requires a single-item pointer handler context");
        }
    }

    const Child = std.meta.Child(ContextPtrType);
    const Stored = PersistedReplayContext(Child);
    const stored = allocator.create(Stored) catch return error.ProgramContractViolation;
    errdefer allocator.destroy(stored);
    stored.arena = std.heap.ArenaAllocator.init(allocator);
    errdefer stored.arena.deinit();

    var clone_state = ReplayCloneState.init(stored.arena.allocator());
    defer clone_state.deinit();
    stored.value = try cloneReplayValue(&clone_state, Child, handler_ctx.*);
    return .{
        .ctx = @ptrCast(&stored.value),
        .cleanup = struct {
            fn cleanup(ctx_allocator: std.mem.Allocator, raw_ctx: ?*anyopaque) void {
                const typed_ctx: *Child = @ptrCast(@alignCast(raw_ctx.?));
                const persisted: *Stored = @fieldParentPtr("value", typed_ctx);
                persisted.arena.deinit();
                ctx_allocator.destroy(persisted);
            }
        }.cleanup,
    };
}

fn findFrame(comptime PromptType: type, prompt: *const PromptType) ?*Frame(PromptType) {
    const prompt_identity: *const anyopaque = @ptrCast(prompt);
    if (lowered_machine.activeRuntime()) |runtime| {
        if (runtime.core.frames.find(*FrameBase, prompt.token)) |runtime_head| {
            var runtime_base = runtime_head;
            while (true) {
                if (runtime_base.prompt_identity == prompt_identity) return @fieldParentPtr("base", runtime_base);
                runtime_base = runtime_base.runtime_previous_for_token orelse break;
            }
        }
    }

    var compat_base = portable_core.compatFrameFind(*FrameBase, prompt.token) orelse return null;
    while (true) {
        if (compat_base.prompt_identity == prompt_identity) return @fieldParentPtr("base", compat_base);
        compat_base = compat_base.compat_previous_for_token orelse return null;
    }
}

fn pushActiveFrame(runtime: *lowered_machine.Runtime, base: *FrameBase) lowered_machine.Error!void {
    const runtime_previous = runtime.core.frames.push(runtime.core.allocator, base.prompt_token, base) catch return error.ProgramContractViolation;
    base.runtime_previous_for_token = if (runtime_previous) |raw| @ptrCast(@alignCast(raw)) else null;
    errdefer {
        const previous: ?*anyopaque = if (base.runtime_previous_for_token) |prior| @ptrCast(prior) else null;
        runtime.core.frames.pop(base.prompt_token, previous);
        base.runtime_previous_for_token = null;
    }

    const compat_previous = portable_core.compatFramePush(runtime.core.allocator, base.prompt_token, base) catch return error.ProgramContractViolation;
    base.compat_previous_for_token = if (compat_previous) |raw| @ptrCast(@alignCast(raw)) else null;
}

fn popActiveFrame(runtime: *lowered_machine.Runtime, base: *FrameBase) void {
    const runtime_previous: ?*anyopaque = if (base.runtime_previous_for_token) |prior| @ptrCast(prior) else null;
    const compat_previous: ?*anyopaque = if (base.compat_previous_for_token) |prior| @ptrCast(prior) else null;
    runtime.core.frames.pop(base.prompt_token, runtime_previous);
    portable_core.compatFramePop(base.prompt_token, compat_previous);
    base.runtime_previous_for_token = null;
    base.compat_previous_for_token = null;
}

fn encodeResume(
    allocator: std.mem.Allocator,
    comptime Resume: type,
    value: Resume,
) lowered_machine.Error![]u8 {
    const size = @sizeOf(Resume);
    const storage = allocator.alloc(u8, size) catch return error.ProgramContractViolation;
    if (size != 0) @memcpy(storage, std.mem.asBytes(&value));
    return storage;
}

fn decodeResume(comptime Resume: type, storage: []const u8) Resume {
    if (storage.len != @sizeOf(Resume)) unreachable;
    if (@sizeOf(Resume) == 0) return;
    return std.mem.bytesToValue(Resume, storage);
}

fn afterResumeThunk(comptime PromptType: type, comptime Handler: type) AfterResumeFn(PromptType) {
    return struct {
        fn invoke(_: ?*anyopaque, value: PromptType.InAnswer) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
            return try callAfterResume(PromptType, Handler, value);
        }
    }.invoke;
}

fn finalizeAnswer(
    comptime PromptType: type,
    frame: *Frame(PromptType),
    value: PromptType.InAnswer,
) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
    if (frame.applied_after.items.len == 0) {
        if (comptime PromptType.InAnswer == PromptType.OutAnswer) return value;
        return error.NonDiagonalComplete;
    }

    if (comptime PromptType.InAnswer == PromptType.OutAnswer) {
        var current: PromptType.OutAnswer = value;
        var index = frame.applied_after.items.len;
        while (index != 0) {
            index -= 1;
            current = try frame.applied_after.items[index].afterResumeFn(frame.applied_after.items[index].ctx, current);
        }
        return current;
    }

    if (frame.applied_after.items.len != 1) return error.ProgramContractViolation;
    return try frame.applied_after.items[0].afterResumeFn(frame.applied_after.items[0].ctx, value);
}

/// Execute one authored body or first-class program under the supplied prompt.
pub fn run(
    runtime: *lowered_machine.Runtime,
    prompt: anytype,
    program: Program(PromptTypeFromPtr(@TypeOf(prompt))),
) lowered_machine.ResetError(PromptErrorSetType(@TypeOf(prompt)))!PromptOutAnswerType(@TypeOf(prompt)) {
    const PromptType = PromptTypeFromPtr(@TypeOf(prompt));

    try lowered_machine.beginExecution(runtime);
    defer lowered_machine.endExecution(runtime);

    switch (program) {
        .abort => |node| return lowered_machine.runExplicitAbort(PromptType, node) catch |err| return @errorCast(err),
        .choice => |node| return lowered_machine.runExplicitChoice(PromptType, node) catch |err| return @errorCast(err),
        .compute => |node| {
            var frame = Frame(PromptType).init(lowered_machine.runtimeAllocator(runtime), prompt);
            defer frame.deinit();
            try pushActiveFrame(runtime, &frame.base);
            defer popActiveFrame(runtime, &frame.base);

            const value = node.invokeFn(node.ctx) catch |err| switch (err) {
                error.FrontendSuspend => {
                    if (frame.terminal) |answer| return answer;
                    return error.FrontendSuspend;
                },
                else => return @errorCast(err),
            };
            return try finalizeAnswer(PromptType, &frame, value);
        },
        .pure => |value| return lowered_machine.runExplicitPure(PromptType, value) catch |err| return @errorCast(err),
        .transform => |node| return lowered_machine.runExplicitTransform(PromptType, node) catch |err| return @errorCast(err),
    }
    unreachable;
}

/// Perform one prompt-delimited operation using replay instead of raw continuation capture.
pub fn perform(
    comptime Resume: type,
    prompt: anytype,
    comptime Handler: type,
) lowered_machine.InternalControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    const PromptType = PromptTypeFromPtr(@TypeOf(prompt));
    comptime assertHandlerProtocol(Resume, PromptType, Handler);

    const frame = findFrame(PromptType, prompt) orelse return error.MissingPrompt;
    if (frame.cursor < frame.records.items.len) {
        const record = frame.records.items[frame.cursor];
        frame.cursor += 1;
        switch (record) {
            .resumed => |recorded| {
                frame.applied_after.append(frame.allocator, .{
                    .ctx = recorded.after_resume_ctx,
                    .afterResumeFn = recorded.afterResumeFn,
                }) catch return error.ProgramContractViolation;
                return decodeResume(Resume, recorded.storage);
            },
            .terminal => |answer| {
                frame.terminal = answer;
                return error.FrontendSuspend;
            },
        }
    }

    switch (PromptType.mode) {
        .resume_then_transform => {
            const resume_value = try callResumeValue(Resume, PromptType, Handler);
            const storage = try encodeResume(frame.allocator, Resume, resume_value);
            frame.records.append(frame.allocator, .{
                .resumed = .{
                    .storage = storage,
                    .after_resume_ctx = null,
                    .afterResumeCleanup = null,
                    .afterResumeFn = afterResumeThunk(PromptType, Handler),
                },
            }) catch return error.ProgramContractViolation;
            return error.FrontendSuspend;
        },
        .resume_or_return => {
            const decision = try callResumeOrReturn(Resume, PromptType, Handler);
            switch (decision) {
                .resume_with => |resume_value| {
                    const storage = try encodeResume(frame.allocator, Resume, resume_value);
                    frame.records.append(frame.allocator, .{
                        .resumed = .{
                            .storage = storage,
                            .after_resume_ctx = null,
                            .afterResumeCleanup = null,
                            .afterResumeFn = afterResumeThunk(PromptType, Handler),
                        },
                    }) catch return error.ProgramContractViolation;
                },
                .return_now => |answer| {
                    frame.terminal = answer;
                    frame.records.append(frame.allocator, .{ .terminal = answer }) catch return error.ProgramContractViolation;
                },
            }
            return error.FrontendSuspend;
        },
        .direct_return => {
            const answer = try callDirectReturn(PromptType, Handler);
            frame.terminal = answer;
            frame.records.append(frame.allocator, .{ .terminal = answer }) catch return error.ProgramContractViolation;
            return error.FrontendSuspend;
        },
    }
}

/// Perform one resumptive transform operation.
pub fn transform(
    comptime Resume: type,
    prompt: anytype,
    comptime Handler: type,
) lowered_machine.InternalControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    comptime assertPromptMode(@TypeOf(prompt), .resume_then_transform, "transform");
    return perform(Resume, prompt, Handler);
}

/// Perform one resumptive transform operation whose handler receives one explicit runtime context pointer.
pub fn transformWithContext(
    comptime Resume: type,
    prompt: anytype,
    handler_ctx: anytype,
    comptime Handler: type,
) lowered_machine.InternalControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    const PromptType = PromptTypeFromPtr(@TypeOf(prompt));
    const ContextPtrType = @TypeOf(handler_ctx);
    comptime assertPromptMode(@TypeOf(prompt), .resume_then_transform, "transformWithContext");
    comptime assertHandlerProtocolWithContext(Resume, PromptType, ContextPtrType, Handler);

    const frame = findFrame(PromptType, prompt) orelse return error.MissingPrompt;
    if (frame.cursor < frame.records.items.len) {
        const record = frame.records.items[frame.cursor];
        frame.cursor += 1;
        switch (record) {
            .resumed => |recorded| {
                frame.applied_after.append(frame.allocator, .{
                    .ctx = recorded.after_resume_ctx,
                    .afterResumeFn = recorded.afterResumeFn,
                }) catch return error.ProgramContractViolation;
                return decodeResume(Resume, recorded.storage);
            },
            .terminal => |answer| {
                frame.terminal = answer;
                return error.FrontendSuspend;
            },
        }
    }

    const resume_value = try callResumeValueWithContext(Resume, PromptType, ContextPtrType, Handler, handler_ctx);
    const storage = try encodeResume(frame.allocator, Resume, resume_value);
    const persisted_ctx = try persistHandlerContext(frame.allocator, ContextPtrType, handler_ctx);
    frame.records.append(frame.allocator, .{
        .resumed = .{
            .storage = storage,
            .after_resume_ctx = persisted_ctx.ctx,
            .afterResumeCleanup = persisted_ctx.cleanup,
            .afterResumeFn = struct {
                fn invoke(raw_ctx: ?*anyopaque, value: PromptType.InAnswer) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
                    const typed_ctx: ContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    return try callAfterResumeWithContext(PromptType, ContextPtrType, Handler, typed_ctx, value);
                }
            }.invoke,
        },
    }) catch {
        if (persisted_ctx.cleanup) |cleanup| cleanup(frame.allocator, persisted_ctx.ctx);
        return error.ProgramContractViolation;
    };
    return error.FrontendSuspend;
}

/// Perform one resumptive transform using a borrowed after-resume context that stays live through the enclosing frontend.run.
pub fn transformWithBorrowedAfterContext(
    comptime Resume: type,
    prompt: anytype,
    resume_value: Resume,
    after_ctx: anytype,
    comptime Handler: type,
) lowered_machine.InternalControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    const PromptType = PromptTypeFromPtr(@TypeOf(prompt));
    const ContextPtrType = @TypeOf(after_ctx);
    comptime assertPromptMode(@TypeOf(prompt), .resume_then_transform, "transformWithBorrowedAfterContext");
    comptime assertBorrowedContextPtrType(ContextPtrType, "transformWithBorrowedAfterContext");
    comptime assertAfterResumeProtocolWithContext(PromptType, ContextPtrType, Handler);

    const frame = findFrame(PromptType, prompt) orelse return error.MissingPrompt;
    if (frame.cursor < frame.records.items.len) {
        const record = frame.records.items[frame.cursor];
        frame.cursor += 1;
        switch (record) {
            .resumed => |recorded| {
                frame.applied_after.append(frame.allocator, .{
                    .ctx = recorded.after_resume_ctx,
                    .afterResumeFn = recorded.afterResumeFn,
                }) catch return error.ProgramContractViolation;
                return decodeResume(Resume, recorded.storage);
            },
            .terminal => |answer| {
                frame.terminal = answer;
                return error.FrontendSuspend;
            },
        }
    }

    const storage = try encodeResume(frame.allocator, Resume, resume_value);
    frame.records.append(frame.allocator, .{
        .resumed = .{
            .storage = storage,
            .after_resume_ctx = @ptrCast(after_ctx),
            .afterResumeCleanup = null,
            .afterResumeFn = struct {
                fn invoke(raw_ctx: ?*anyopaque, value: PromptType.InAnswer) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
                    const typed_ctx: ContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                    return try callAfterResumeWithContext(PromptType, ContextPtrType, Handler, typed_ctx, value);
                }
            }.invoke,
        },
    }) catch return error.ProgramContractViolation;
    return error.FrontendSuspend;
}

/// Perform one zero-or-one-resume choice operation.
pub fn choice(
    comptime Resume: type,
    prompt: anytype,
    comptime Handler: type,
) lowered_machine.InternalControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    comptime assertPromptMode(@TypeOf(prompt), .resume_or_return, "choice");
    return perform(Resume, prompt, Handler);
}

/// Perform one zero-or-one-resume choice operation whose handler receives one explicit runtime context pointer.
pub fn choiceWithContext(
    comptime Resume: type,
    prompt: anytype,
    handler_ctx: anytype,
    comptime Handler: type,
) lowered_machine.InternalControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    const PromptType = PromptTypeFromPtr(@TypeOf(prompt));
    const ContextPtrType = @TypeOf(handler_ctx);
    comptime assertPromptMode(@TypeOf(prompt), .resume_or_return, "choiceWithContext");
    comptime assertHandlerProtocolWithContext(Resume, PromptType, ContextPtrType, Handler);

    const frame = findFrame(PromptType, prompt) orelse return error.MissingPrompt;
    if (frame.cursor < frame.records.items.len) {
        const record = frame.records.items[frame.cursor];
        frame.cursor += 1;
        switch (record) {
            .resumed => |recorded| {
                frame.applied_after.append(frame.allocator, .{
                    .ctx = recorded.after_resume_ctx,
                    .afterResumeFn = recorded.afterResumeFn,
                }) catch return error.ProgramContractViolation;
                return decodeResume(Resume, recorded.storage);
            },
            .terminal => |answer| {
                frame.terminal = answer;
                return error.FrontendSuspend;
            },
        }
    }

    const decision = try callResumeOrReturnWithContext(Resume, PromptType, ContextPtrType, Handler, handler_ctx);
    switch (decision) {
        .resume_with => |resume_value| {
            const storage = try encodeResume(frame.allocator, Resume, resume_value);
            const persisted_ctx = try persistHandlerContext(frame.allocator, ContextPtrType, handler_ctx);
            frame.records.append(frame.allocator, .{
                .resumed = .{
                    .storage = storage,
                    .after_resume_ctx = persisted_ctx.ctx,
                    .afterResumeCleanup = persisted_ctx.cleanup,
                    .afterResumeFn = struct {
                        fn invoke(raw_ctx: ?*anyopaque, value: PromptType.InAnswer) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
                            const typed_ctx: ContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                            return try callAfterResumeWithContext(PromptType, ContextPtrType, Handler, typed_ctx, value);
                        }
                    }.invoke,
                },
            }) catch {
                if (persisted_ctx.cleanup) |cleanup| cleanup(frame.allocator, persisted_ctx.ctx);
                return error.ProgramContractViolation;
            };
        },
        .return_now => |answer| {
            frame.terminal = answer;
            frame.records.append(frame.allocator, .{ .terminal = answer }) catch return error.ProgramContractViolation;
        },
    }
    return error.FrontendSuspend;
}

/// Perform one zero-or-one-resume choice using a borrowed after-resume context that stays live through the enclosing frontend.run.
pub fn choiceWithBorrowedAfterContext(
    comptime Resume: type,
    prompt: anytype,
    decision: ResumeOrReturnType(Resume, PromptTypeFromPtr(@TypeOf(prompt))),
    after_ctx: anytype,
    comptime Handler: type,
) lowered_machine.InternalControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    const PromptType = PromptTypeFromPtr(@TypeOf(prompt));
    const ContextPtrType = @TypeOf(after_ctx);
    comptime assertPromptMode(@TypeOf(prompt), .resume_or_return, "choiceWithBorrowedAfterContext");
    comptime assertBorrowedContextPtrType(ContextPtrType, "choiceWithBorrowedAfterContext");
    comptime assertAfterResumeProtocolWithContext(PromptType, ContextPtrType, Handler);

    const frame = findFrame(PromptType, prompt) orelse return error.MissingPrompt;
    if (frame.cursor < frame.records.items.len) {
        const record = frame.records.items[frame.cursor];
        frame.cursor += 1;
        switch (record) {
            .resumed => |recorded| {
                frame.applied_after.append(frame.allocator, .{
                    .ctx = recorded.after_resume_ctx,
                    .afterResumeFn = recorded.afterResumeFn,
                }) catch return error.ProgramContractViolation;
                return decodeResume(Resume, recorded.storage);
            },
            .terminal => |answer| {
                frame.terminal = answer;
                return error.FrontendSuspend;
            },
        }
    }

    switch (decision) {
        .resume_with => |resume_value| {
            const storage = try encodeResume(frame.allocator, Resume, resume_value);
            frame.records.append(frame.allocator, .{
                .resumed = .{
                    .storage = storage,
                    .after_resume_ctx = @ptrCast(after_ctx),
                    .afterResumeCleanup = null,
                    .afterResumeFn = struct {
                        fn invoke(raw_ctx: ?*anyopaque, value: PromptType.InAnswer) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
                            const typed_ctx: ContextPtrType = @ptrCast(@alignCast(raw_ctx.?));
                            return try callAfterResumeWithContext(PromptType, ContextPtrType, Handler, typed_ctx, value);
                        }
                    }.invoke,
                },
            }) catch return error.ProgramContractViolation;
        },
        .return_now => |answer| {
            frame.terminal = answer;
            frame.records.append(frame.allocator, .{ .terminal = answer }) catch return error.ProgramContractViolation;
        },
    }
    return error.FrontendSuspend;
}

/// Perform one direct-return abort operation.
pub fn abort(
    prompt: anytype,
    comptime Handler: type,
) lowered_machine.InternalControlError(PromptErrorSetType(@TypeOf(prompt)))!noreturn {
    comptime assertPromptMode(@TypeOf(prompt), .direct_return, "abort");
    _ = try perform(void, prompt, Handler);
    unreachable;
}

/// Perform one direct-return abort operation whose handler receives one explicit runtime context pointer.
pub fn abortWithContext(
    prompt: anytype,
    handler_ctx: anytype,
    comptime Handler: type,
) lowered_machine.InternalControlError(PromptErrorSetType(@TypeOf(prompt)))!noreturn {
    const PromptType = PromptTypeFromPtr(@TypeOf(prompt));
    const ContextPtrType = @TypeOf(handler_ctx);
    comptime assertPromptMode(@TypeOf(prompt), .direct_return, "abortWithContext");
    comptime assertHandlerProtocolWithContext(void, PromptType, ContextPtrType, Handler);

    const frame = findFrame(PromptType, prompt) orelse return error.MissingPrompt;
    if (frame.cursor < frame.records.items.len) {
        const record = frame.records.items[frame.cursor];
        frame.cursor += 1;
        switch (record) {
            .terminal => |answer| {
                frame.terminal = answer;
                return error.FrontendSuspend;
            },
            .resumed => return error.ProgramContractViolation,
        }
    }

    const answer = try callDirectReturnWithContext(PromptType, ContextPtrType, Handler, handler_ctx);
    frame.terminal = answer;
    frame.records.append(frame.allocator, .{ .terminal = answer }) catch return error.ProgramContractViolation;
    return error.FrontendSuspend;
}

test "transformWithContext persists a copy of handler context for replay" {
    const Prompt = prompt_contract.Prompt(.resume_then_transform, i32, i32, error{});
    const Metadata = struct {
        offset: i32,
    };
    const Carrier = struct {
        tag: usize,
        payload: i32,
        metadata: *Metadata,
        label: []const u8,
    };
    const handler = struct {
        /// Return the resumptive transform payload from the persisted carrier copy.
        pub fn resumeValue(ctx: *Carrier) i32 {
            return ctx.payload;
        }

        /// Return one observable value from the persisted carrier copy after resume.
        pub fn afterResume(ctx: *Carrier, answer: i32) i32 {
            return answer + @as(i32, @intCast(ctx.tag)) + ctx.metadata.offset + @as(i32, ctx.label[0]);
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try lowered_machine.beginExecution(&runtime);
    defer lowered_machine.endExecution(&runtime);

    var prompt = Prompt.init();
    var frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &prompt);
    defer frame.deinit();
    try pushActiveFrame(&runtime, &frame.base);
    defer popActiveFrame(&runtime, &frame.base);

    var metadata = Metadata{ .offset = 3 };
    var label_storage = [_]u8{ 'A', 'B' };
    var carrier = Carrier{ .tag = 7, .payload = 41, .metadata = &metadata, .label = label_storage[0..] };
    try std.testing.expectError(error.FrontendSuspend, transformWithContext(i32, &prompt, &carrier, handler));
    try std.testing.expectEqual(@as(usize, 1), frame.records.items.len);

    const resumed = frame.records.items[0].resumed;
    try std.testing.expect(resumed.after_resume_ctx != @as(?*anyopaque, @ptrCast(&carrier)));
    const stored: *Carrier = @ptrCast(@alignCast(resumed.after_resume_ctx.?));
    try std.testing.expectEqual(@as(usize, 7), stored.tag);
    try std.testing.expectEqual(@as(i32, 41), stored.payload);
    try std.testing.expect(stored.metadata != carrier.metadata);
    try std.testing.expect(stored.label.ptr != carrier.label.ptr);
    try std.testing.expectEqual(@as(i32, 3), stored.metadata.offset);
    try std.testing.expectEqualStrings("AB", stored.label);

    carrier.tag = 99;
    carrier.payload = 0;
    carrier.metadata.offset = 20;
    label_storage[0] = 'Z';
    try std.testing.expectEqual(@as(usize, 7), stored.tag);
    try std.testing.expectEqual(@as(i32, 41), stored.payload);
    try std.testing.expectEqual(@as(i32, 3), stored.metadata.offset);
    try std.testing.expectEqualStrings("AB", stored.label);
    try std.testing.expectEqual(@as(i32, 80), try resumed.afterResumeFn(resumed.after_resume_ctx, 5));
}

test "transformWithContext rebinds allocator-backed replay state to the persisted clone allocator" {
    const Prompt = prompt_contract.Prompt(.resume_then_transform, i32, i32, error{OutOfMemory});
    const Carrier = struct {
        list: std.ArrayList(i32),
        allocator: std.mem.Allocator,
    };
    const handler = struct {
        /// Return the first replayed element from the managed list copy.
        pub fn resumeValue(ctx: *Carrier) i32 {
            return ctx.list.items[0];
        }

        /// Append through the rebound allocator to prove the replay copy owns its storage.
        pub fn afterResume(ctx: *Carrier, answer: i32) error{OutOfMemory}!i32 {
            defer ctx.list.deinit(ctx.allocator);
            try ctx.list.append(ctx.allocator, answer);
            return ctx.list.items[0] + ctx.list.items[1];
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try lowered_machine.beginExecution(&runtime);
    defer lowered_machine.endExecution(&runtime);

    var prompt = Prompt.init();
    var frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &prompt);
    defer frame.deinit();
    try pushActiveFrame(&runtime, &frame.base);
    defer popActiveFrame(&runtime, &frame.base);

    var original_buffer: [256]u8 = undefined;
    var original_allocator = std.heap.FixedBufferAllocator.init(&original_buffer);
    var carrier = Carrier{
        .list = .empty,
        .allocator = original_allocator.allocator(),
    };
    defer carrier.list.deinit(carrier.allocator);
    try carrier.list.append(carrier.allocator, 7);

    try std.testing.expectError(error.FrontendSuspend, transformWithContext(i32, &prompt, &carrier, handler));
    const resumed = frame.records.items[0].resumed;
    const stored: *Carrier = @ptrCast(@alignCast(resumed.after_resume_ctx.?));
    const allocator_rebound = stored.allocator.ptr != carrier.allocator.ptr or
        stored.allocator.vtable != carrier.allocator.vtable;
    try std.testing.expect(allocator_rebound);
    try std.testing.expect(stored.list.items.ptr != carrier.list.items.ptr);
    try std.testing.expectEqual(stored.list.items.len, stored.list.capacity);
    try std.testing.expectEqual(@as(i32, 18), try resumed.afterResumeFn(resumed.after_resume_ctx, 11));
}

test "transformWithContext preserves aliased pointer fields during replay" {
    const Prompt = prompt_contract.Prompt(.resume_then_transform, i32, i32, error{});
    const Shared = struct {
        value: i32,
    };
    const Carrier = struct {
        left: *Shared,
        right: *Shared,
    };
    const handler = struct {
        /// Return the shared replay payload from the aliased pointer pair.
        pub fn resumeValue(ctx: *Carrier) i32 {
            return ctx.left.value;
        }

        /// Mutate one aliased edge and read back through the other.
        pub fn afterResume(ctx: *Carrier, answer: i32) i32 {
            ctx.left.value += answer;
            return ctx.right.value;
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try lowered_machine.beginExecution(&runtime);
    defer lowered_machine.endExecution(&runtime);

    var prompt = Prompt.init();
    var frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &prompt);
    defer frame.deinit();
    try pushActiveFrame(&runtime, &frame.base);
    defer popActiveFrame(&runtime, &frame.base);

    var shared = Shared{ .value = 41 };
    var carrier = Carrier{ .left = &shared, .right = &shared };
    try std.testing.expectError(error.FrontendSuspend, transformWithContext(i32, &prompt, &carrier, handler));

    const resumed = frame.records.items[0].resumed;
    const stored: *Carrier = @ptrCast(@alignCast(resumed.after_resume_ctx.?));
    try std.testing.expect(stored.left == stored.right);
    try std.testing.expect(stored.left != carrier.left);

    shared.value = 0;
    try std.testing.expectEqual(@as(i32, 41), stored.left.value);
    try std.testing.expectEqual(@as(i32, 42), try resumed.afterResumeFn(resumed.after_resume_ctx, 1));
}

test "transformWithContext preserves aliased slice backing storage during replay" {
    const Prompt = prompt_contract.Prompt(.resume_then_transform, i32, i32, error{});
    const Carrier = struct {
        left: []i32,
        right: []i32,
    };
    const handler = struct {
        /// Return the shared replay payload from the aliased slice pair.
        pub fn resumeValue(ctx: *Carrier) i32 {
            return ctx.left[0];
        }

        /// Mutate one slice view and read back through the aliased peer.
        pub fn afterResume(ctx: *Carrier, answer: i32) i32 {
            ctx.left[0] += answer;
            return ctx.right[0];
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try lowered_machine.beginExecution(&runtime);
    defer lowered_machine.endExecution(&runtime);

    var prompt = Prompt.init();
    var frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &prompt);
    defer frame.deinit();
    try pushActiveFrame(&runtime, &frame.base);
    defer popActiveFrame(&runtime, &frame.base);

    var shared = [_]i32{ 41, 99 };
    var carrier = Carrier{
        .left = shared[0..1],
        .right = shared[0..1],
    };
    try std.testing.expectError(error.FrontendSuspend, transformWithContext(i32, &prompt, &carrier, handler));

    const resumed = frame.records.items[0].resumed;
    const stored: *Carrier = @ptrCast(@alignCast(resumed.after_resume_ctx.?));
    try std.testing.expect(stored.left.ptr == stored.right.ptr);
    try std.testing.expect(stored.left.ptr != carrier.left.ptr);

    shared[0] = 0;
    try std.testing.expectEqual(@as(i32, 41), stored.left[0]);
    try std.testing.expectEqual(@as(i32, 42), try resumed.afterResumeFn(resumed.after_resume_ctx, 1));
}

test "transform replay keeps frames disambiguated across independent prompt sources" {
    const Prompt = prompt_contract.Prompt(.resume_then_transform, i32, i32, error{});
    const handler = struct {
        fn resumeValue() i32 {
            return 41;
        }

        fn afterResume(answer: i32) i32 {
            return answer;
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try lowered_machine.beginExecution(&runtime);
    defer lowered_machine.endExecution(&runtime);

    var first_source = portable_core.PromptTokenSource{};
    var second_source = portable_core.PromptTokenSource{};
    var first_prompt = Prompt.initWithSource(&first_source);
    var second_prompt = Prompt.initWithSource(&second_source);
    try std.testing.expect(first_prompt.token != second_prompt.token);

    var first_frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &first_prompt);
    defer first_frame.deinit();
    try pushActiveFrame(&runtime, &first_frame.base);
    defer popActiveFrame(&runtime, &first_frame.base);

    var second_frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &second_prompt);
    defer second_frame.deinit();
    try pushActiveFrame(&runtime, &second_frame.base);
    defer popActiveFrame(&runtime, &second_frame.base);

    try std.testing.expectError(error.FrontendSuspend, transform(i32, &first_prompt, handler));
    try std.testing.expectEqual(@as(usize, 1), first_frame.records.items.len);
    try std.testing.expectEqual(@as(usize, 0), second_frame.records.items.len);
}

test "compat frame pop restores the shadowed frame when runtimes reuse a prompt token" {
    const Prompt = prompt_contract.Prompt(.resume_then_transform, i32, i32, error{});

    var first_runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer first_runtime.deinit();
    var second_runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer second_runtime.deinit();

    var first_prompt = Prompt.initWithToken(41);
    var second_prompt = Prompt.initWithToken(41);

    var first_frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&first_runtime), &first_prompt);
    defer first_frame.deinit();
    try pushActiveFrame(&first_runtime, &first_frame.base);

    try std.testing.expect(findFrame(Prompt, &first_prompt) == &first_frame);
    try std.testing.expect(first_runtime.core.frames.find(*FrameBase, first_prompt.token) == &first_frame.base);

    var second_frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&second_runtime), &second_prompt);
    defer second_frame.deinit();
    try pushActiveFrame(&second_runtime, &second_frame.base);

    try std.testing.expect(findFrame(Prompt, &second_prompt) == &second_frame);
    try std.testing.expect(second_runtime.core.frames.find(*FrameBase, second_prompt.token) == &second_frame.base);

    popActiveFrame(&second_runtime, &second_frame.base);
    try std.testing.expect(findFrame(Prompt, &first_prompt) == &first_frame);
    try std.testing.expect(first_runtime.core.frames.find(*FrameBase, first_prompt.token) == &first_frame.base);
    try std.testing.expect(second_runtime.core.frames.find(*FrameBase, second_prompt.token) == null);

    popActiveFrame(&first_runtime, &first_frame.base);
    try std.testing.expect(findFrame(Prompt, &first_prompt) == null);
    try std.testing.expect(first_runtime.core.frames.find(*FrameBase, first_prompt.token) == null);
}

test "compat frame lookup keeps prompt-token collisions isolated while both runtimes stay active" {
    const Prompt = prompt_contract.Prompt(.resume_then_transform, i32, i32, error{});
    const handler = struct {
        /// Return one distinct resumptive value for the collision regression.
        pub fn resumeValue() i32 {
            return 41;
        }

        /// Preserve the resumed answer so only frame routing affects the test.
        pub fn afterResume(answer: i32) i32 {
            return answer;
        }
    };

    var first_runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer first_runtime.deinit();
    var second_runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer second_runtime.deinit();

    var first_prompt = Prompt.initWithToken(41);
    var second_prompt = Prompt.initWithToken(41);

    var first_frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&first_runtime), &first_prompt);
    defer first_frame.deinit();
    try pushActiveFrame(&first_runtime, &first_frame.base);
    defer popActiveFrame(&first_runtime, &first_frame.base);

    var second_frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&second_runtime), &second_prompt);
    defer second_frame.deinit();
    try pushActiveFrame(&second_runtime, &second_frame.base);
    defer popActiveFrame(&second_runtime, &second_frame.base);

    try std.testing.expect(findFrame(Prompt, &first_prompt) == &first_frame);
    try std.testing.expect(findFrame(Prompt, &second_prompt) == &second_frame);

    try lowered_machine.beginExecution(&first_runtime);
    defer lowered_machine.endExecution(&first_runtime);

    try std.testing.expectError(error.FrontendSuspend, transform(i32, &first_prompt, handler));
    try std.testing.expectEqual(@as(usize, 1), first_frame.records.items.len);
    try std.testing.expectEqual(@as(usize, 0), second_frame.records.items.len);
}

test "runtime frame lookup keeps prompt-token collisions isolated inside one runtime" {
    const Prompt = prompt_contract.Prompt(.resume_then_transform, i32, i32, error{});
    const handler = struct {
        /// Return one distinct resumptive value for the same-runtime collision regression.
        pub fn resumeValue() i32 {
            return 41;
        }

        /// Preserve the resumed answer so only frame routing affects the test.
        pub fn afterResume(answer: i32) i32 {
            return answer;
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var first_prompt = Prompt.initWithToken(41);
    var second_prompt = Prompt.initWithToken(41);

    var first_frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &first_prompt);
    defer first_frame.deinit();
    try pushActiveFrame(&runtime, &first_frame.base);
    defer popActiveFrame(&runtime, &first_frame.base);

    var second_frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &second_prompt);
    defer second_frame.deinit();
    try pushActiveFrame(&runtime, &second_frame.base);
    defer popActiveFrame(&runtime, &second_frame.base);

    try std.testing.expect(runtime.core.frames.find(*FrameBase, first_prompt.token) == &second_frame.base);
    try std.testing.expect(findFrame(Prompt, &first_prompt) == &first_frame);
    try std.testing.expect(findFrame(Prompt, &second_prompt) == &second_frame);

    try lowered_machine.beginExecution(&runtime);
    defer lowered_machine.endExecution(&runtime);

    try std.testing.expectError(error.FrontendSuspend, transform(i32, &first_prompt, handler));
    try std.testing.expectEqual(@as(usize, 1), first_frame.records.items.len);
    try std.testing.expectEqual(@as(usize, 0), second_frame.records.items.len);
}

test "runtime frame lookup returns null for same-token prompts that were never pushed" {
    const Prompt = prompt_contract.Prompt(.resume_then_transform, i32, i32, error{});
    const handler = struct {
        /// Return one distinct resumptive value for the MissingPrompt regression.
        pub fn resumeValue() i32 {
            return 41;
        }

        /// Preserve the resumed answer so only frame routing affects the test.
        pub fn afterResume(answer: i32) i32 {
            return answer;
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var pushed_prompt = Prompt.initWithToken(41);
    var orphan_prompt = Prompt.initWithToken(41);

    var frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &pushed_prompt);
    defer frame.deinit();
    try pushActiveFrame(&runtime, &frame.base);
    defer popActiveFrame(&runtime, &frame.base);

    try lowered_machine.beginExecution(&runtime);
    defer lowered_machine.endExecution(&runtime);

    try std.testing.expect(findFrame(Prompt, &orphan_prompt) == null);
    try std.testing.expectError(error.MissingPrompt, transform(i32, &orphan_prompt, handler));
}

test "findFrame falls back to compat frames when an active inner runtime misses an outer prompt" {
    const Prompt = prompt_contract.Prompt(.resume_then_transform, i32, i32, error{});
    const handler = struct {
        /// Return one distinct resumptive value for the active-runtime fallback regression.
        pub fn resumeValue() i32 {
            return 41;
        }

        /// Preserve the resumed answer so only frame routing affects the test.
        pub fn afterResume(answer: i32) i32 {
            return answer;
        }
    };

    var outer_runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer outer_runtime.deinit();
    var inner_runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer inner_runtime.deinit();

    var outer_prompt = Prompt.initWithToken(41);
    var inner_prompt = Prompt.initWithToken(42);

    var outer_frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&outer_runtime), &outer_prompt);
    defer outer_frame.deinit();
    try pushActiveFrame(&outer_runtime, &outer_frame.base);
    defer popActiveFrame(&outer_runtime, &outer_frame.base);

    var inner_frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&inner_runtime), &inner_prompt);
    defer inner_frame.deinit();
    try pushActiveFrame(&inner_runtime, &inner_frame.base);
    defer popActiveFrame(&inner_runtime, &inner_frame.base);

    try lowered_machine.beginExecution(&outer_runtime);
    defer lowered_machine.endExecution(&outer_runtime);
    try lowered_machine.beginExecution(&inner_runtime);
    defer lowered_machine.endExecution(&inner_runtime);

    try std.testing.expect(findFrame(Prompt, &outer_prompt) == &outer_frame);
    try std.testing.expectError(error.FrontendSuspend, transform(i32, &outer_prompt, handler));
    try std.testing.expectEqual(@as(usize, 1), outer_frame.records.items.len);
    try std.testing.expectEqual(@as(usize, 0), inner_frame.records.items.len);
}

test "choiceWithContext persists a copy of handler context for replay" {
    const Prompt = prompt_contract.Prompt(.resume_or_return, i32, i32, error{});
    const Carrier = struct {
        tag: usize,
        payload: i32,
    };
    const handler = struct {
        /// Resume the choice with the carrier payload from the persisted copy.
        pub fn resumeOrReturn(ctx: *Carrier) ResumeOrReturnType(i32, Prompt) {
            return ResumeOrReturnType(i32, Prompt).resumeWith(ctx.payload);
        }

        /// Return one observable value from the persisted carrier copy after resume.
        pub fn afterResume(ctx: *Carrier, answer: i32) i32 {
            return answer + @as(i32, @intCast(ctx.tag));
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try lowered_machine.beginExecution(&runtime);
    defer lowered_machine.endExecution(&runtime);

    var prompt = Prompt.init();
    var frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &prompt);
    defer frame.deinit();
    try pushActiveFrame(&runtime, &frame.base);
    defer popActiveFrame(&runtime, &frame.base);

    var carrier = Carrier{ .tag = 11, .payload = 52 };
    try std.testing.expectError(error.FrontendSuspend, choiceWithContext(i32, &prompt, &carrier, handler));
    try std.testing.expectEqual(@as(usize, 1), frame.records.items.len);

    const resumed = frame.records.items[0].resumed;
    try std.testing.expect(resumed.after_resume_ctx != @as(?*anyopaque, @ptrCast(&carrier)));
    const stored: *Carrier = @ptrCast(@alignCast(resumed.after_resume_ctx.?));
    try std.testing.expectEqual(@as(usize, 11), stored.tag);
    try std.testing.expectEqual(@as(i32, 52), stored.payload);

    carrier.tag = 101;
    carrier.payload = 0;
    try std.testing.expectEqual(@as(usize, 11), stored.tag);
    try std.testing.expectEqual(@as(i32, 52), stored.payload);
}

test "transformWithBorrowedAfterContext keeps live handler state for replay" {
    const Prompt = prompt_contract.Prompt(.resume_then_transform, i32, i32, error{});
    const Carrier = struct {
        offset: *i32,
    };
    const handler = struct {
        /// Read the live borrowed offset when the transform replay finalizes.
        pub fn afterResume(ctx: *Carrier, answer: i32) i32 {
            return answer + ctx.offset.*;
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try lowered_machine.beginExecution(&runtime);
    defer lowered_machine.endExecution(&runtime);

    var prompt = Prompt.init();
    var frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &prompt);
    defer frame.deinit();
    try pushActiveFrame(&runtime, &frame.base);
    defer popActiveFrame(&runtime, &frame.base);

    var offset: i32 = 3;
    var carrier = Carrier{ .offset = &offset };
    try std.testing.expectError(error.FrontendSuspend, transformWithBorrowedAfterContext(i32, &prompt, 41, &carrier, handler));
    try std.testing.expectEqual(@as(usize, 1), frame.records.items.len);

    offset = 7;
    const resumed = frame.records.items[0].resumed;
    try std.testing.expectEqual(@as(i32, 12), try resumed.afterResumeFn(resumed.after_resume_ctx, 5));
}

test "choiceWithBorrowedAfterContext keeps live handler state for replay" {
    const Prompt = prompt_contract.Prompt(.resume_or_return, i32, i32, error{});
    const Carrier = struct {
        offset: *i32,
    };
    const handler = struct {
        /// Read the live borrowed offset when the choice replay finalizes.
        pub fn afterResume(ctx: *Carrier, answer: i32) i32 {
            return answer + ctx.offset.*;
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try lowered_machine.beginExecution(&runtime);
    defer lowered_machine.endExecution(&runtime);

    var prompt = Prompt.init();
    var frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &prompt);
    defer frame.deinit();
    try pushActiveFrame(&runtime, &frame.base);
    defer popActiveFrame(&runtime, &frame.base);

    var offset: i32 = 5;
    var carrier = Carrier{ .offset = &offset };
    const decision = ResumeOrReturnType(i32, Prompt).resumeWith(41);
    try std.testing.expectError(error.FrontendSuspend, choiceWithBorrowedAfterContext(i32, &prompt, decision, &carrier, handler));
    try std.testing.expectEqual(@as(usize, 1), frame.records.items.len);

    offset = 11;
    const resumed = frame.records.items[0].resumed;
    try std.testing.expectEqual(@as(i32, 16), try resumed.afterResumeFn(resumed.after_resume_ctx, 5));
}

test "abortWithContext reuses the recorded terminal during replay" {
    const Prompt = prompt_contract.Prompt(.direct_return, void, i32, error{});
    const Carrier = struct {
        calls: usize = 0,
        answer: i32,
    };
    const handler = struct {
        /// Return the recorded terminal answer from the supplied carrier.
        pub fn directReturn(ctx: *Carrier) i32 {
            ctx.calls += 1;
            return ctx.answer;
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try lowered_machine.beginExecution(&runtime);
    defer lowered_machine.endExecution(&runtime);

    var prompt = Prompt.init();
    var frame = Frame(Prompt).init(lowered_machine.runtimeAllocator(&runtime), &prompt);
    defer frame.deinit();
    try pushActiveFrame(&runtime, &frame.base);
    defer popActiveFrame(&runtime, &frame.base);

    var carrier = Carrier{ .answer = 41 };
    try std.testing.expectError(error.FrontendSuspend, abortWithContext(&prompt, &carrier, handler));
    try std.testing.expectEqual(@as(usize, 1), carrier.calls);
    try std.testing.expectEqual(@as(usize, 1), frame.records.items.len);
    try std.testing.expectEqual(@as(i32, 41), frame.terminal.?);

    frame.terminal = null;
    try std.testing.expectError(error.FrontendSuspend, abortWithContext(&prompt, &carrier, handler));
    try std.testing.expectEqual(@as(usize, 1), carrier.calls);
    try std.testing.expectEqual(@as(usize, 1), frame.records.items.len);
    try std.testing.expectEqual(@as(i32, 41), frame.terminal.?);
}
