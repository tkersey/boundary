const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const std = @import("std");

const EncodedValue = lowered_machine.ProgramValue;

const FrameBase = struct {
    prompt_token: prompt_contract.PromptToken,
    parent: ?*FrameBase = null,
};

threadlocal var active_frame: ?*FrameBase = null;

fn PromptTypeFromPtr(comptime PromptPtrType: type) type {
    return switch (@typeInfo(PromptPtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to shift.Prompt(...)"),
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

fn fnParamsMatch(comptime FnType: type, comptime ParamTypes: []const type) bool {
    const actual = @typeInfo(FnType).@"fn".params;
    if (actual.len != ParamTypes.len) return false;
    inline for (ParamTypes, 0..) |ParamType, index| {
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
            directReturnFn: *const fn () lowered_machine.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer,
        },
        choice: struct {
            decisionFn: *const fn () lowered_machine.ControlError(PromptType.ErrorSet)!DecisionValue(PromptType),
            continueFn: *const fn (EncodedValue) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer,
            afterResumeFn: AfterResumeFn(PromptType),
        },
        compute: *const fn () lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.InAnswer,
        pure: PromptType.InAnswer,
        transform: struct {
            resumeValueFn: *const fn () lowered_machine.ControlError(PromptType.ErrorSet)!EncodedValue,
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
    return .{ .compute = normalizeBodyFn(PromptType, thunk) };
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
            .resumeValueFn = struct {
                fn invoke() lowered_machine.ControlError(PromptType.ErrorSet)!EncodedValue {
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
            .decisionFn = struct {
                fn invoke() lowered_machine.ControlError(PromptType.ErrorSet)!DecisionValue(PromptType) {
                    const decision = try callResumeOrReturn(Resume, PromptType, Handler);
                    return switch (decision) {
                        .resume_with => |value| .{ .resume_with = try encodeValue(Resume, value) },
                        .return_now => |answer| .{ .return_now = answer },
                    };
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

/// Build one explicit abortive program with a single direct-return operation.
pub fn abortProgram(
    comptime PromptType: type,
    comptime Handler: type,
) Program(PromptType) {
    comptime assertPromptTypeMode(PromptType, .direct_return, "abortProgram");
    comptime assertHandlerProtocol(void, PromptType, Handler);
    return .{
        .abort = .{
            .directReturnFn = struct {
                fn invoke() lowered_machine.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer {
                    return try callDirectReturn(PromptType, Handler);
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

/// Read the allocator from any runtime-like pointer that carries the canonical lifecycle fields.
fn runtimeAllocator(runtime: anytype) std.mem.Allocator {
    const RuntimePtrType = @TypeOf(runtime);
    const RuntimeType = switch (@typeInfo(RuntimePtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to a runtime value"),
    };
    if (!@hasField(RuntimeType, "allocator") or !@hasField(RuntimeType, "thread_id") or !@hasField(RuntimeType, "state") or !@hasField(RuntimeType, "active_reset_count")) {
        @compileError("expected a runtime-like pointer with allocator/thread_id/state/active_reset_count");
    }
    return runtime.allocator;
}

fn ensureRuntime(runtime: anytype) lowered_machine.Error!void {
    if (runtime.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
    if (runtime.state == .destroyed) return error.RuntimeDestroyed;
}

fn AfterResumeFn(comptime PromptType: type) type {
    return *const fn (PromptType.InAnswer) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer;
}

fn ResumeRecord(comptime PromptType: type) type {
    return union(enum) {
        resumed: struct {
            storage: []u8,
            afterResumeFn: AfterResumeFn(PromptType),
        },
        terminal: PromptType.OutAnswer,
    };
}

fn Frame(comptime PromptType: type) type {
    return struct {
        base: FrameBase,
        allocator: std.mem.Allocator,
        records: std.ArrayList(ResumeRecord(PromptType)) = .empty,
        applied_after: std.ArrayList(AfterResumeFn(PromptType)) = .empty,
        cursor: usize = 0,
        terminal: ?PromptType.OutAnswer = null,

        fn init(allocator: std.mem.Allocator, prompt: *const PromptType) @This() {
            return .{
                .base = .{ .prompt_token = prompt.token },
                .allocator = allocator,
            };
        }

        fn deinit(self: *@This()) void {
            for (self.records.items) |record| switch (record) {
                .resumed => |resumed| self.allocator.free(resumed.storage),
                .terminal => {},
            };
            self.records.deinit(self.allocator);
            self.applied_after.deinit(self.allocator);
        }
    };
}

fn findFrame(comptime PromptType: type, prompt: *const PromptType) ?*Frame(PromptType) {
    var base = active_frame;
    while (base) |current| : (base = current.parent) {
        if (current.prompt_token == prompt.token) {
            return @fieldParentPtr("base", current);
        }
    }
    return null;
}

fn pushActiveFrame(base: *FrameBase) void {
    base.parent = active_frame;
    active_frame = base;
}

fn popActiveFrame(base: *FrameBase) void {
    active_frame = base.parent;
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
        fn invoke(value: PromptType.InAnswer) lowered_machine.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
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
            current = try frame.applied_after.items[index](current);
        }
        return current;
    }

    if (frame.applied_after.items.len != 1) return error.ProgramContractViolation;
    return try frame.applied_after.items[0](value);
}

/// Execute one authored body or first-class program under the supplied prompt.
pub fn run(
    runtime: anytype,
    prompt: anytype,
    program: Program(PromptTypeFromPtr(@TypeOf(prompt))),
) lowered_machine.ResetError(PromptErrorSetType(@TypeOf(prompt)))!PromptOutAnswerType(@TypeOf(prompt)) {
    const PromptType = PromptTypeFromPtr(@TypeOf(prompt));

    try ensureRuntime(runtime);
    runtime.active_reset_count += 1;
    defer runtime.active_reset_count -= 1;

    switch (program) {
        .abort => |node| return lowered_machine.runExplicitAbort(PromptType, node) catch |err| return @errorCast(err),
        .choice => |node| return lowered_machine.runExplicitChoice(PromptType, node) catch |err| return @errorCast(err),
        .compute => |node| {
            var frame = Frame(PromptType).init(runtimeAllocator(runtime), prompt);
            defer frame.deinit();
            pushActiveFrame(&frame.base);
            defer popActiveFrame(&frame.base);

            const value = node() catch |err| switch (err) {
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
                frame.applied_after.append(frame.allocator, recorded.afterResumeFn) catch return error.ProgramContractViolation;
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

/// Perform one zero-or-one-resume choice operation.
pub fn choice(
    comptime Resume: type,
    prompt: anytype,
    comptime Handler: type,
) lowered_machine.InternalControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    comptime assertPromptMode(@TypeOf(prompt), .resume_or_return, "choice");
    return perform(Resume, prompt, Handler);
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
