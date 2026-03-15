const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract.zig");
const raw = @import("raw.zig");
const std = @import("std");

const max_records = 32;
const max_resume_bytes = 64;

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

fn expectDeclTypeOneOf(comptime Owner: type, comptime name: []const u8, comptime ExpectedA: type, comptime ExpectedB: type) void {
    if (!hasDeclSafe(Owner, name)) {
        @compileError(@typeName(Owner) ++ " must declare " ++ name);
    }
    const ActualType = @TypeOf(@field(Owner, name));
    if (ActualType != ExpectedA and ActualType != ExpectedB) {
        @compileError(
            @typeName(Owner) ++ "." ++ name ++ " must have type " ++ @typeName(ExpectedA) ++
                " or " ++ @typeName(ExpectedB),
        );
    }
}

fn ResumeOrReturnType(comptime Resume: type, comptime PromptType: type) type {
    return raw.ResumeOrReturn(Resume, PromptType.OutAnswer);
}

fn assertHandlerProtocol(comptime Resume: type, comptime PromptType: type, comptime Handler: type) void {
    switch (PromptType.mode) {
        .resume_or_return => {
            expectDeclTypeOneOf(
                Handler,
                "resumeOrReturn",
                fn () ResumeOrReturnType(Resume, PromptType),
                fn () raw.ResetError(PromptType.ErrorSet)!ResumeOrReturnType(Resume, PromptType),
            );
            expectDeclTypeOneOf(
                Handler,
                "afterResume",
                fn (PromptType.InAnswer) PromptType.OutAnswer,
                fn (PromptType.InAnswer) raw.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer,
            );
        },
        .resume_then_transform => {
            expectDeclTypeOneOf(
                Handler,
                "resumeValue",
                fn () Resume,
                fn () raw.ResetError(PromptType.ErrorSet)!Resume,
            );
            expectDeclTypeOneOf(
                Handler,
                "afterResume",
                fn (PromptType.InAnswer) PromptType.OutAnswer,
                fn (PromptType.InAnswer) raw.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer,
            );
        },
        .direct_return => {
            expectDeclTypeOneOf(
                Handler,
                "directReturn",
                fn () PromptType.OutAnswer,
                fn () raw.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer,
            );
        },
    }
}

fn callResumeValue(comptime Resume: type, comptime PromptType: type, comptime Handler: type) raw.ControlError(PromptType.ErrorSet)!Resume {
    const ResumeFn = @TypeOf(Handler.resumeValue);
    if (ResumeFn == fn () Resume) return Handler.resumeValue();
    return Handler.resumeValue() catch |err| return @errorCast(err);
}

fn callAfterResume(
    comptime PromptType: type,
    comptime Handler: type,
    value: PromptType.InAnswer,
) raw.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer {
    const AfterFn = @TypeOf(Handler.afterResume);
    if (AfterFn == fn (PromptType.InAnswer) PromptType.OutAnswer) return Handler.afterResume(value);
    return Handler.afterResume(value) catch |err| return @errorCast(err);
}

fn callDirectReturn(comptime PromptType: type, comptime Handler: type) raw.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer {
    const DirectFn = @TypeOf(Handler.directReturn);
    if (DirectFn == fn () PromptType.OutAnswer) return Handler.directReturn();
    return Handler.directReturn() catch |err| return @errorCast(err);
}

fn callResumeOrReturn(comptime Resume: type, comptime PromptType: type, comptime Handler: type) raw.ControlError(PromptType.ErrorSet)!ResumeOrReturnType(Resume, PromptType) {
    const ResumeOrReturnFn = @TypeOf(Handler.resumeOrReturn);
    if (ResumeOrReturnFn == fn () ResumeOrReturnType(Resume, PromptType)) return Handler.resumeOrReturn();
    return Handler.resumeOrReturn() catch |err| return @errorCast(err);
}

fn assertContinuationType(
    comptime Input: type,
    comptime PromptType: type,
    comptime Continuation: type,
) void {
    expectDeclTypeOneOf(
        Continuation,
        "apply",
        fn (Input) PromptType.InAnswer,
        fn (Input) raw.ResetError(PromptType.ErrorSet)!PromptType.InAnswer,
    );
}

fn callContinuation(
    comptime Input: type,
    comptime PromptType: type,
    comptime Continuation: type,
    value: Input,
) raw.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
    const ApplyFn = @TypeOf(Continuation.apply);
    if (ApplyFn == fn (Input) PromptType.InAnswer) return Continuation.apply(value);
    return Continuation.apply(value) catch |err| return @errorCast(err);
}

fn encodeValue(comptime T: type, value: T) raw.Error!EncodedValue {
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
            directReturnFn: *const fn () raw.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer,
        },
        choice: struct {
            decisionFn: *const fn () raw.ControlError(PromptType.ErrorSet)!DecisionValue(PromptType),
            continueFn: *const fn (EncodedValue) raw.ResetError(PromptType.ErrorSet)!PromptType.InAnswer,
            afterResumeFn: AfterResumeFn(PromptType),
        },
        legacy_body: *const fn () raw.ResetError(PromptType.ErrorSet)!PromptType.InAnswer,
        pure: PromptType.InAnswer,
        transform: struct {
            resumeValueFn: *const fn () raw.ControlError(PromptType.ErrorSet)!EncodedValue,
            continueFn: *const fn (EncodedValue) raw.ResetError(PromptType.ErrorSet)!PromptType.InAnswer,
            afterResumeFn: AfterResumeFn(PromptType),
        },
    };
}

/// Wrap one authored body function in a first-class program shell.
fn fromBody(
    comptime PromptType: type,
    body: anytype,
) Program(PromptType) {
    return .{ .legacy_body = normalizeBodyFn(PromptType, body) };
}

/// Build one explicit canonical program from a body spec type.
pub fn build(
    comptime PromptType: type,
    comptime Spec: type,
) Program(PromptType) {
    return fromBody(PromptType, @field(Spec, "body"));
}

/// Build a pure explicit program for prompts whose body answer is already final.
pub fn pureProgram(comptime PromptType: type, value: PromptType.InAnswer) Program(PromptType) {
    return .{ .pure = value };
}

/// Build one explicit transform program with a single resumptive operation.
pub fn transformProgram(
    comptime PromptType: type,
    comptime Resume: type,
    comptime Handler: type,
    comptime Continuation: type,
) Program(PromptType) {
    comptime assertPromptTypeMode(PromptType, .resume_then_transform, "transformProgram");
    comptime assertHandlerProtocol(Resume, PromptType, Handler);
    comptime assertContinuationType(Resume, PromptType, Continuation);
    return .{
        .transform = .{
            .resumeValueFn = struct {
                fn invoke() raw.ControlError(PromptType.ErrorSet)!EncodedValue {
                    return try encodeValue(Resume, try callResumeValue(Resume, PromptType, Handler));
                }
            }.invoke,
            .continueFn = struct {
                fn invoke(value: EncodedValue) raw.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
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
    comptime Continuation: type,
) Program(PromptType) {
    comptime assertPromptTypeMode(PromptType, .resume_or_return, "choiceProgram");
    comptime assertHandlerProtocol(Resume, PromptType, Handler);
    comptime assertContinuationType(Resume, PromptType, Continuation);
    return .{
        .choice = .{
            .decisionFn = struct {
                fn invoke() raw.ControlError(PromptType.ErrorSet)!DecisionValue(PromptType) {
                    const decision = try callResumeOrReturn(Resume, PromptType, Handler);
                    return switch (decision) {
                        .resume_with => |value| .{ .resume_with = try encodeValue(Resume, value) },
                        .return_now => |answer| .{ .return_now = answer },
                    };
                }
            }.invoke,
            .continueFn = struct {
                fn invoke(value: EncodedValue) raw.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
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
                fn invoke() raw.ControlError(PromptType.ErrorSet)!PromptType.OutAnswer {
                    return try callDirectReturn(PromptType, Handler);
                }
            }.invoke,
        },
    };
}

fn normalizeBodyFn(
    comptime PromptType: type,
    body: anytype,
) *const fn () raw.ResetError(PromptType.ErrorSet)!PromptType.InAnswer {
    const InputType = @TypeOf(body);
    const BodyPtrType = *const fn () raw.ResetError(PromptType.ErrorSet)!PromptType.InAnswer;
    const BodyFnType = fn () raw.ResetError(PromptType.ErrorSet)!PromptType.InAnswer;

    if (InputType == BodyPtrType) return body;
    if (InputType == BodyFnType) return body;

    @compileError("expected authored body with type fn () ResetError(ErrorSet)!InAnswer");
}

/// Accept either a first-class program or an authored body function for the supplied prompt type.
fn coerceProgram(comptime PromptType: type, body_or_program: anytype) Program(PromptType) {
    const InputType = @TypeOf(body_or_program);
    if (InputType == Program(PromptType)) return body_or_program;
    return fromBody(PromptType, body_or_program);
}

/// Normalize either a canonical runtime wrapper or a raw runtime pointer to the active execution engine.
pub fn unwrapRuntimePtr(runtime: anytype) *raw.Runtime {
    const RuntimePtrType = @TypeOf(runtime);
    const RuntimeType = switch (@typeInfo(RuntimePtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to a runtime value"),
    };
    if (RuntimeType == raw.Runtime) return runtime;
    if (@hasField(RuntimeType, "inner") and @FieldType(RuntimeType, "inner") == raw.Runtime) {
        return &runtime.inner;
    }
    @compileError("expected *raw.Runtime or a canonical runtime wrapper around raw.Runtime");
}

fn ensureRuntime(runtime: *raw.Runtime) raw.Error!void {
    if (runtime.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
    if (runtime.state == .destroyed) return error.RuntimeDestroyed;
}

fn AfterResumeFn(comptime PromptType: type) type {
    return *const fn (PromptType.InAnswer) raw.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer;
}

fn ResumeRecord(comptime PromptType: type) type {
    return union(enum) {
        resumed: struct {
            storage: [max_resume_bytes]u8,
            size: usize,
            afterResumeFn: AfterResumeFn(PromptType),
        },
        terminal: PromptType.OutAnswer,
    };
}

fn Frame(comptime PromptType: type) type {
    return struct {
        base: FrameBase,
        runtime: *raw.Runtime,
        records: [max_records]?ResumeRecord(PromptType) = [_]?ResumeRecord(PromptType){null} ** max_records,
        records_len: usize = 0,
        applied_after: [max_records]?AfterResumeFn(PromptType) = [_]?AfterResumeFn(PromptType){null} ** max_records,
        applied_after_len: usize = 0,
        cursor: usize = 0,
        terminal: ?PromptType.OutAnswer = null,

        fn init(runtime: *raw.Runtime, prompt: *const PromptType) @This() {
            return .{
                .base = .{ .prompt_token = prompt.token },
                .runtime = runtime,
            };
        }

        fn deinit(_: *@This()) void {
            // Fixed-capacity replay storage does not own heap allocations.
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
    comptime Resume: type,
    value: Resume,
) raw.Error!struct {
    storage: [max_resume_bytes]u8,
    size: usize,
} {
    const size = @sizeOf(Resume);
    if (size > max_resume_bytes) return error.ProgramContractViolation;
    var storage = [_]u8{0} ** max_resume_bytes;
    if (size != 0) @memcpy(storage[0..size], std.mem.asBytes(&value));
    return .{ .storage = storage, .size = size };
}

fn decodeResume(comptime Resume: type, storage: [max_resume_bytes]u8, expected_size: usize) Resume {
    if (expected_size != @sizeOf(Resume)) unreachable;
    if (@sizeOf(Resume) == 0) return;
    return std.mem.bytesToValue(Resume, storage[0..@sizeOf(Resume)]);
}

fn afterResumeThunk(comptime PromptType: type, comptime Handler: type) AfterResumeFn(PromptType) {
    return struct {
        fn invoke(value: PromptType.InAnswer) raw.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
            return try callAfterResume(PromptType, Handler, value);
        }
    }.invoke;
}

fn finalizeAnswer(
    comptime PromptType: type,
    frame: *Frame(PromptType),
    value: PromptType.InAnswer,
) raw.ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
    if (frame.applied_after_len == 0) {
        if (comptime PromptType.InAnswer == PromptType.OutAnswer) return value;
        return error.NonDiagonalComplete;
    }

    if (comptime PromptType.InAnswer == PromptType.OutAnswer) {
        var current: PromptType.OutAnswer = value;
        var index = frame.applied_after_len;
        while (index != 0) {
            index -= 1;
            current = try frame.applied_after[index].?(current);
        }
        return current;
    }

    if (frame.applied_after_len != 1) return error.ProgramContractViolation;
    return try frame.applied_after[0].?(value);
}

/// Execute one authored body or first-class program under the supplied prompt.
pub fn run(
    runtime: anytype,
    prompt: anytype,
    body_or_program: anytype,
) raw.ResetError(PromptErrorSetType(@TypeOf(prompt)))!PromptOutAnswerType(@TypeOf(prompt)) {
    const PromptType = PromptTypeFromPtr(@TypeOf(prompt));
    const program = coerceProgram(PromptType, body_or_program);
    const raw_runtime = unwrapRuntimePtr(runtime);

    try ensureRuntime(raw_runtime);
    raw_runtime.active_reset_count += 1;
    defer raw_runtime.active_reset_count -= 1;

    switch (program) {
        .abort, .choice, .pure, .transform => return lowered_machine.runExplicitProgram(PromptType, program) catch |err| return @errorCast(err),
        .legacy_body => {},
    }

    var frame = Frame(PromptType).init(raw_runtime, prompt);
    defer frame.deinit();
    pushActiveFrame(&frame.base);
    defer popActiveFrame(&frame.base);

    while (true) {
        frame.cursor = 0;
        frame.terminal = null;
        frame.applied_after_len = 0;

        const value = program.legacy_body() catch |err| switch (err) {
            error.FrontendSuspend => {
                if (frame.terminal) |answer| return answer;
                continue;
            },
            else => return err,
        };

        return try finalizeAnswer(PromptType, &frame, value);
    }
}

/// Perform one prompt-delimited operation using replay instead of raw continuation capture.
pub fn perform(
    comptime Resume: type,
    prompt: anytype,
    comptime Handler: type,
) raw.ControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    const PromptType = PromptTypeFromPtr(@TypeOf(prompt));
    comptime assertHandlerProtocol(Resume, PromptType, Handler);

    const frame = findFrame(PromptType, prompt) orelse return error.MissingPrompt;
    if (frame.cursor < frame.records_len) {
        const record = frame.records[frame.cursor].?;
        frame.cursor += 1;
        switch (record) {
            .resumed => |recorded| {
                if (frame.applied_after_len == max_records) return error.ProgramContractViolation;
                frame.applied_after[frame.applied_after_len] = recorded.afterResumeFn;
                frame.applied_after_len += 1;
                return decodeResume(Resume, recorded.storage, recorded.size);
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
            const encoded = try encodeResume(Resume, resume_value);
            if (frame.records_len == max_records) return error.ProgramContractViolation;
            frame.records[frame.records_len] = .{
                .resumed = .{
                    .storage = encoded.storage,
                    .size = encoded.size,
                    .afterResumeFn = afterResumeThunk(PromptType, Handler),
                },
            };
            frame.records_len += 1;
            return error.FrontendSuspend;
        },
        .resume_or_return => {
            const decision = try callResumeOrReturn(Resume, PromptType, Handler);
            switch (decision) {
                .resume_with => |resume_value| {
                    const encoded = try encodeResume(Resume, resume_value);
                    if (frame.records_len == max_records) return error.ProgramContractViolation;
                    frame.records[frame.records_len] = .{
                        .resumed = .{
                            .storage = encoded.storage,
                            .size = encoded.size,
                            .afterResumeFn = afterResumeThunk(PromptType, Handler),
                        },
                    };
                    frame.records_len += 1;
                },
                .return_now => |answer| {
                    frame.terminal = answer;
                    if (frame.records_len == max_records) return error.ProgramContractViolation;
                    frame.records[frame.records_len] = .{ .terminal = answer };
                    frame.records_len += 1;
                },
            }
            return error.FrontendSuspend;
        },
        .direct_return => {
            const answer = try callDirectReturn(PromptType, Handler);
            frame.terminal = answer;
            if (frame.records_len == max_records) return error.ProgramContractViolation;
            frame.records[frame.records_len] = .{ .terminal = answer };
            frame.records_len += 1;
            return error.FrontendSuspend;
        },
    }
}

/// Perform one resumptive transform operation.
pub fn transform(
    comptime Resume: type,
    prompt: anytype,
    comptime Handler: type,
) raw.ControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    comptime assertPromptMode(@TypeOf(prompt), .resume_then_transform, "transform");
    return perform(Resume, prompt, Handler);
}

/// Perform one zero-or-one-resume choice operation.
pub fn choice(
    comptime Resume: type,
    prompt: anytype,
    comptime Handler: type,
) raw.ControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    comptime assertPromptMode(@TypeOf(prompt), .resume_or_return, "choice");
    return perform(Resume, prompt, Handler);
}

/// Perform one direct-return abort operation.
pub fn abort(
    prompt: anytype,
    comptime Handler: type,
) raw.ControlError(PromptErrorSetType(@TypeOf(prompt)))!noreturn {
    comptime assertPromptMode(@TypeOf(prompt), .direct_return, "abort");
    _ = try perform(void, prompt, Handler);
    unreachable;
}
