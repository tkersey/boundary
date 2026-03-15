const builtin = @import("builtin");
const std = @import("std");

/// Runtime errors surfaced by the fiber-backed control core.
pub const Error = error{
    AlreadyResolved,
    CrossThread,
    MissingPrompt,
    NestedNonDiagonalCapture,
    NonDiagonalComplete,
    RuntimeBusy,
    RuntimeDestroyed,
};

/// Setup failures that can occur before user code enters `reset`.
pub const SetupError = error{OutOfMemory} || std.posix.MMapError || std.posix.MProtectError;

/// Runtime-visible error union for user-provided errors.
pub fn ControlError(comptime ErrorSet: type) type {
    return Error || ErrorSet;
}

/// Full `reset`-path error union including setup failures.
pub fn ResetError(comptime ErrorSet: type) type {
    return ControlError(ErrorSet) || SetupError;
}

/// Comptime-selected handler protocol attached to a prompt value.
pub const PromptMode = enum {
    direct_return,
    resume_or_return,
    resume_then_transform,
};

/// Handler decision for zero-or-one-resume prompt modes.
pub fn ResumeOrReturn(
    comptime ResumeType: type,
    comptime OutAnswerType: type,
) type {
    return union(enum) {
        resume_with: ResumeType,
        return_now: OutAnswerType,

        /// Complete the enclosing prompt without resuming the captured continuation.
        pub fn returnNow(value: OutAnswerType) @This() {
            return .{ .return_now = value };
        }

        /// Resume once with `value`, then let the handler's `afterResume` complete the enclosing answer.
        pub fn resumeWith(value: ResumeType) @This() {
            return .{ .resume_with = value };
        }
    };
}

/// Thread-affine runtime that owns stackful continuations.
pub const Runtime = struct {
    const default_guard_pages: usize = 1;
    const default_stack_bytes: usize = 256 * 1024;

    allocator: std.mem.Allocator,
    options: Options,
    thread_id: std.Thread.Id,
    state: enum {
        alive,
        destroyed,
    } = .alive,
    root_context: Context = .{},
    active_reset_count: usize = 0,
    cached_stacks: std.ArrayList(Stack) = .empty,

    /// Public compatibility fields retained while the lowered runtime swap is in flight.
    pub const Options = struct {
        stack_bytes: usize = default_stack_bytes,
        guard_pages: usize = default_guard_pages,
        max_cached_stacks: usize = 16,
    };

    /// Initialize a runtime on the current thread.
    pub fn init(allocator: std.mem.Allocator, options: Options) Runtime {
        return .{
            .allocator = allocator,
            .options = options,
            .thread_id = std.Thread.getCurrentId(),
        };
    }

    /// Release cached stacks owned by the runtime.
    pub fn deinit(self: *Runtime) void {
        self.deinitChecked() catch |err| switch (err) {
            error.CrossThread, error.RuntimeBusy => unreachable,
            else => unreachable,
        };
    }

    /// Release cached stacks owned by the runtime, returning an error on misuse.
    pub fn deinitChecked(self: *Runtime) Error!void {
        try self.ensureThread();
        if (self.state == .destroyed) return error.RuntimeDestroyed;
        if (self.active_reset_count != 0) return error.RuntimeBusy;
        var i: usize = 0;
        while (i < self.cached_stacks.items.len) : (i += 1) {
            self.cached_stacks.items[i].deinit();
        }
        self.cached_stacks.deinit(self.allocator);
        self.cached_stacks = .empty;
        self.state = .destroyed;
    }

    fn ensureThread(self: *Runtime) Error!void {
        if (self.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
        if (self.state == .destroyed) return error.RuntimeDestroyed;
    }

    fn ensureEnteredRuntime(self: *Runtime) Error!void {
        if (self.state == .destroyed) return error.RuntimeDestroyed;
        if (tls_runtime == self) return;
        if (self.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
    }

    fn acquireStack(self: *Runtime) !Stack {
        if (self.cached_stacks.pop()) |stack| return stack;
        return Stack.init(self.options);
    }

    fn releaseStack(self: *Runtime, stack: Stack) void {
        if (self.cached_stacks.items.len >= self.options.max_cached_stacks) {
            stack.deinit();
            return;
        }
        self.cached_stacks.append(self.allocator, stack) catch {
            stack.deinit();
        };
    }
};

const page_size = std.heap.page_size_min;

const Stack = struct {
    mapping: []align(page_size) u8,
    usable: []u8,

    fn init(options: Runtime.Options) !Stack {
        _ = options.stack_bytes;
        _ = options.guard_pages;
        const guard_bytes = Runtime.default_guard_pages * page_size;
        const total = Runtime.default_stack_bytes + guard_bytes;
        const mapping = try std.posix.mmap(
            null,
            total,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        );
        if (guard_bytes != 0) {
            try std.posix.mprotect(mapping[0..guard_bytes], std.posix.PROT.NONE);
        }
        return .{
            .mapping = mapping,
            .usable = mapping[guard_bytes..],
        };
    }

    fn deinit(self: Stack) void {
        std.posix.munmap(self.mapping);
    }

    fn top(self: Stack) usize {
        return @intFromPtr(self.usable.ptr) + self.usable.len;
    }
};

const PromptToken = usize;

var prompt_token_mutex: std.Thread.Mutex = .{};
var next_prompt_token: PromptToken = 1;

fn allocatePromptToken() PromptToken {
    prompt_token_mutex.lock();
    defer prompt_token_mutex.unlock();
    const token = next_prompt_token;
    next_prompt_token += 1;
    return token;
}

/// First-class prompt value for one-shot `shift/reset`.
pub fn Prompt(
    comptime mode_type: PromptMode,
    comptime InAnswerType: type,
    comptime OutAnswerType: type,
    comptime ErrorSetType: type,
) type {
    return struct {
        /// Comptime-selected handler protocol for this prompt.
        pub const mode = mode_type;
        /// Answer type produced by the resumed subcontinuation.
        pub const InAnswer = InAnswerType;
        /// Enclosing answer type of the delimited computation.
        pub const OutAnswer = OutAnswerType;
        /// User error set carried through this prompt value.
        pub const ErrorSet = ErrorSetType;

        token: PromptToken,

        /// Create a fresh prompt value with distinct delimiter identity.
        pub fn init() @This() {
            return .{ .token = allocatePromptToken() };
        }
    };
}

const Context = switch (builtin.cpu.arch) {
    .x86_64 => extern struct {
        rsp: usize = 0,
        rbx: usize = 0,
        rbp: usize = 0,
        r12: usize = 0,
        r13: usize = 0,
        r14: usize = 0,
        r15: usize = 0,
        rip: usize = 0,
    },
    .aarch64 => extern struct {
        spv: usize = 0,
        x19: usize = 0,
        x20: usize = 0,
        x21: usize = 0,
        x22: usize = 0,
        x23: usize = 0,
        x24: usize = 0,
        x25: usize = 0,
        x26: usize = 0,
        x27: usize = 0,
        x28: usize = 0,
        fpv: usize = 0,
        lrv: usize = 0,
    },
    else => @compileError("shift currently supports x86_64 and aarch64 hosts only"),
};

extern fn shift_swap_context(from: *Context, to: *const Context) callconv(.c) void;

threadlocal var tls_runtime: ?*Runtime = null;
threadlocal var tls_current_fiber: ?*FiberBase = null;

const FiberState = enum {
    done,
    failed,
    ready,
    running,
    suspended,
};

const FiberOutcome = union(enum) {
    captured: *CaptureBase,
    none,
};

const FiberBase = struct {
    runtime: *Runtime,
    parent_fiber: ?*FiberBase,
    parent_context: *Context,
    context: Context = .{},
    stack: Stack,
    prompt_token: PromptToken,
    state: FiberState = .ready,
    outcome: FiberOutcome = .none,
    abandonFn: *const fn (*FiberBase) void,
    startFn: *const fn (*FiberBase) noreturn,
};

const CaptureBase = struct {
    invokeFn: *const fn (*CaptureBase, *anyopaque) anyerror!void,
    source_fiber: *FiberBase,
    target_fiber: *FiberBase,
};

fn ResetFrame(comptime PromptType: type) type {
    const InAnswer = PromptType.InAnswer;
    const ErrorSet = PromptType.ErrorSet;
    return struct {
        base: FiberBase,
        body: *const fn () ResetError(ErrorSet)!InAnswer,
        result: union(enum) {
            err: ResetError(ErrorSet),
            in_answer: InAnswer,
            none,
        } = .none,

        fn init(runtime: *Runtime, prompt: *const PromptType, body: *const fn () ResetError(ErrorSet)!InAnswer) ResetError(ErrorSet)!@This() {
            const parent_fiber = tls_current_fiber;
            const parent_context = if (parent_fiber) |fiber| &fiber.context else &runtime.root_context;
            const stack = try runtime.acquireStack();
            return .{
                .base = .{
                    .runtime = runtime,
                    .parent_fiber = parent_fiber,
                    .parent_context = parent_context,
                    .stack = stack,
                    .prompt_token = prompt.token,
                    .abandonFn = abandon,
                    .startFn = start,
                },
                .body = body,
            };
        }

        fn setup(self: *@This()) void {
            initializeContext(&self.base.context, self.base.stack.top());
        }

        fn deinit(self: *@This()) void {
            self.base.runtime.releaseStack(self.base.stack);
        }

        fn abandon(base: *FiberBase) void {
            const self: *@This() = @fieldParentPtr("base", base);
            std.debug.assert(self.base.state == .suspended);
            std.debug.assert(self.base.runtime.active_reset_count != 0);
            self.base.state = .failed;
            self.base.outcome = .none;
            self.deinit();
            self.base.runtime.active_reset_count -= 1;
        }

        fn start(base: *FiberBase) noreturn {
            const self: *@This() = @fieldParentPtr("base", base);
            tls_runtime = base.runtime;
            tls_current_fiber = base;
            base.state = .running;
            const answer = self.body() catch |err| finishCurrentFiberWithError(PromptType, self, err);
            finishCurrentFiberWithAnswer(PromptType, self, answer);
        }
    };
}

fn initializeContext(context: *Context, stack_top: usize) void {
    switch (builtin.cpu.arch) {
        .x86_64 => {
            const aligned = stack_top & ~@as(usize, 0xF);
            context.rsp = aligned;
            context.rip = @intFromPtr(&shiftFiberEntry);
        },
        .aarch64 => {
            const aligned = stack_top & ~@as(usize, 0xF);
            context.spv = aligned;
            context.lrv = @intFromPtr(&shiftFiberEntry);
        },
        else => unreachable,
    }
}

export fn shiftFiberEntry() callconv(.c) noreturn {
    const fiber = tls_current_fiber.?;
    fiber.startFn(fiber);
}

fn finishCurrentFiberWithAnswer(comptime PromptType: type, frame: anytype, answer: PromptType.InAnswer) noreturn {
    frame.result = .{ .in_answer = answer };
    frame.base.state = .done;
    frame.base.outcome = .none;
    tls_current_fiber = frame.base.parent_fiber;
    shift_swap_context(&frame.base.context, frame.base.parent_context);
    unreachable;
}

fn finishCurrentFiberWithError(comptime PromptType: type, frame: anytype, err: ResetError(PromptType.ErrorSet)) noreturn {
    frame.result = .{ .err = err };
    frame.base.state = .failed;
    frame.base.outcome = .none;
    tls_current_fiber = frame.base.parent_fiber;
    shift_swap_context(&frame.base.context, frame.base.parent_context);
    unreachable;
}

fn defineResetFrameStart(comptime PromptType: type) void {
    _ = PromptType;
}

fn DriveFrameOutAnswer(comptime PromptType: type) type {
    const InAnswer = PromptType.InAnswer;
    const OutAnswer = PromptType.OutAnswer;
    const ErrorSet = PromptType.ErrorSet;
    return struct {
        fn run(frame: anytype) ResetError(ErrorSet)!OutAnswer {
            const runtime = frame.base.runtime;
            try runtime.ensureEnteredRuntime();
            const previous_runtime = tls_runtime;
            const previous_fiber = tls_current_fiber;
            defer {
                tls_runtime = previous_runtime;
                tls_current_fiber = previous_fiber;
            }

            while (true) {
                tls_runtime = runtime;
                tls_current_fiber = &frame.base;
                shift_swap_context(frame.base.parent_context, &frame.base.context);
                switch (frame.base.state) {
                    .done => switch (frame.result) {
                        .in_answer => |answer| {
                            if (comptime InAnswer == OutAnswer) return answer;
                            return error.NonDiagonalComplete;
                        },
                        else => unreachable,
                    },
                    .failed => switch (frame.result) {
                        .err => |err| return err,
                        else => unreachable,
                    },
                    .suspended => switch (frame.base.outcome) {
                        .captured => |capture| {
                            if (capture.target_fiber != &frame.base) {
                                const active_parent = tls_current_fiber.?;
                                active_parent.state = .suspended;
                                active_parent.outcome = .{ .captured = capture };
                                tls_current_fiber = active_parent.parent_fiber;
                                shift_swap_context(&active_parent.context, active_parent.parent_context);
                                continue;
                            }
                            var answer: ?OutAnswer = null;
                            capture.invokeFn(capture, @ptrCast(&answer)) catch |err| return @errorCast(err);
                            return answer.?;
                        },
                        else => unreachable,
                    },
                    else => unreachable,
                }
            }
        }
    };
}

fn DriveFrameInAnswer(comptime PromptType: type) type {
    const InAnswer = PromptType.InAnswer;
    const OutAnswer = PromptType.OutAnswer;
    const ErrorSet = PromptType.ErrorSet;
    return struct {
        fn run(frame: *ResetFrame(PromptType)) ResetError(ErrorSet)!InAnswer {
            const runtime = frame.base.runtime;
            try runtime.ensureEnteredRuntime();
            const previous_runtime = tls_runtime;
            const previous_fiber = tls_current_fiber;
            defer {
                tls_runtime = previous_runtime;
                tls_current_fiber = previous_fiber;
            }

            while (true) {
                tls_runtime = runtime;
                tls_current_fiber = &frame.base;
                shift_swap_context(frame.base.parent_context, &frame.base.context);
                switch (frame.base.state) {
                    .done => switch (frame.result) {
                        .in_answer => |answer| return answer,
                        else => unreachable,
                    },
                    .failed => switch (frame.result) {
                        .err => |err| return err,
                        else => unreachable,
                    },
                    .suspended => switch (frame.base.outcome) {
                        .captured => |capture| {
                            if (capture.target_fiber != &frame.base) {
                                const active_parent = tls_current_fiber.?;
                                active_parent.state = .suspended;
                                active_parent.outcome = .{ .captured = capture };
                                tls_current_fiber = active_parent.parent_fiber;
                                shift_swap_context(&active_parent.context, active_parent.parent_context);
                                continue;
                            }
                            if (comptime InAnswer != OutAnswer) {
                                return error.NestedNonDiagonalCapture;
                            }
                            var answer: ?OutAnswer = null;
                            capture.invokeFn(capture, @ptrCast(&answer)) catch |err| return @errorCast(err);
                            return answer.?;
                        },
                        else => unreachable,
                    },
                    else => unreachable,
                }
            }
        }
    };
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
    return ResumeOrReturn(Resume, PromptType.OutAnswer);
}

fn assertHandlerProtocol(comptime Resume: type, comptime PromptType: type, comptime Handler: type) void {
    switch (PromptType.mode) {
        .resume_or_return => {
            expectDeclTypeOneOf(
                Handler,
                "resumeOrReturn",
                fn () ResumeOrReturnType(Resume, PromptType),
                fn () ResetError(PromptType.ErrorSet)!ResumeOrReturnType(Resume, PromptType),
            );
            expectDeclTypeOneOf(
                Handler,
                "afterResume",
                fn (PromptType.InAnswer) PromptType.OutAnswer,
                fn (PromptType.InAnswer) ResetError(PromptType.ErrorSet)!PromptType.OutAnswer,
            );
        },
        .resume_then_transform => {
            expectDeclTypeOneOf(
                Handler,
                "resumeValue",
                fn () Resume,
                fn () ResetError(PromptType.ErrorSet)!Resume,
            );
            expectDeclTypeOneOf(
                Handler,
                "afterResume",
                fn (PromptType.InAnswer) PromptType.OutAnswer,
                fn (PromptType.InAnswer) ResetError(PromptType.ErrorSet)!PromptType.OutAnswer,
            );
        },
        .direct_return => {
            expectDeclTypeOneOf(
                Handler,
                "directReturn",
                fn () PromptType.OutAnswer,
                fn () ResetError(PromptType.ErrorSet)!PromptType.OutAnswer,
            );
        },
    }
}

fn callResumeValue(comptime Resume: type, comptime PromptType: type, comptime Handler: type) ResetError(PromptType.ErrorSet)!Resume {
    const ResumeFn = @TypeOf(Handler.resumeValue);
    if (ResumeFn == fn () Resume) return Handler.resumeValue();
    return try Handler.resumeValue();
}

fn callAfterResume(
    comptime PromptType: type,
    comptime Handler: type,
    value: PromptType.InAnswer,
) ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
    const AfterFn = @TypeOf(Handler.afterResume);
    if (AfterFn == fn (PromptType.InAnswer) PromptType.OutAnswer) return Handler.afterResume(value);
    return try Handler.afterResume(value);
}

fn callDirectReturn(comptime PromptType: type, comptime Handler: type) ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
    const DirectFn = @TypeOf(Handler.directReturn);
    if (DirectFn == fn () PromptType.OutAnswer) return Handler.directReturn();
    return try Handler.directReturn();
}

fn callResumeOrReturn(comptime Resume: type, comptime PromptType: type, comptime Handler: type) ResetError(PromptType.ErrorSet)!ResumeOrReturnType(Resume, PromptType) {
    const ResumeOrReturnFn = @TypeOf(Handler.resumeOrReturn);
    if (ResumeOrReturnFn == fn () ResumeOrReturnType(Resume, PromptType)) return Handler.resumeOrReturn();
    return try Handler.resumeOrReturn();
}

fn abandonIntermediateFibers(source_fiber: *FiberBase, target_fiber: *FiberBase) void {
    var fiber = source_fiber;
    while (fiber != target_fiber) {
        const next = fiber.parent_fiber.?;
        fiber.abandonFn(fiber);
        fiber = next;
    }
}

/// One-shot continuation handle for a captured `shift`.
fn Continuation(comptime Resume: type, comptime PromptType: type, comptime Capture: type) type {
    const InAnswer = PromptType.InAnswer;
    const ErrorSet = PromptType.ErrorSet;
    return struct {
        capture: *Capture,

        /// Resume the captured continuation once with `value`.
        pub fn resumeWith(self: *@This(), value: Resume) ResetError(ErrorSet)!InAnswer {
            if (self.capture.consumed) return error.AlreadyResolved;
            self.capture.consumed = true;
            self.capture.disposition = .resumed;
            self.capture.resume_value = value;
            return DriveFrameInAnswer(PromptType).run(self.capture.target_frame);
        }
    };
}

fn ShiftCapture(comptime Resume: type, comptime PromptType: type, comptime Handler: type) type {
    const OutAnswer = PromptType.OutAnswer;
    return struct {
        base: CaptureBase,
        target_frame: *ResetFrame(PromptType),
        consumed: bool = false,
        disposition: enum {
            pending,
            resumed,
        } = .pending,
        resume_value: ?Resume = null,

        fn invoke(base: *CaptureBase, answer_out: *anyopaque) anyerror!void {
            const self: *@This() = @fieldParentPtr("base", base);
            const out: *?OutAnswer = @ptrCast(@alignCast(answer_out));
            out.* = switch (PromptType.mode) {
                .resume_or_return => blk: {
                    const decision = try callResumeOrReturn(Resume, PromptType, Handler);
                    switch (decision) {
                        .return_now => |answer| {
                            abandonIntermediateFibers(self.base.source_fiber, self.base.target_fiber);
                            break :blk answer;
                        },
                        .resume_with => |value| {
                            var continuation = Continuation(Resume, PromptType, @This()){ .capture = self };
                            const answer = try continuation.resumeWith(value);
                            break :blk try callAfterResume(PromptType, Handler, answer);
                        },
                    }
                },
                .resume_then_transform => blk: {
                    var continuation = Continuation(Resume, PromptType, @This()){ .capture = self };
                    const answer = try continuation.resumeWith(try callResumeValue(Resume, PromptType, Handler));
                    break :blk try callAfterResume(PromptType, Handler, answer);
                },
                .direct_return => blk: {
                    const answer = try callDirectReturn(PromptType, Handler);
                    abandonIntermediateFibers(self.base.source_fiber, self.base.target_fiber);
                    break :blk answer;
                },
            };
        }
    };
}

/// Run `body` under a fresh delimiter identified by `prompt`.
pub fn reset(
    comptime PromptType: type,
    runtime: *Runtime,
    prompt: *const PromptType,
    body: *const fn () ResetError(PromptType.ErrorSet)!PromptType.InAnswer,
) ResetError(PromptType.ErrorSet)!PromptType.OutAnswer {
    try runtime.ensureThread();
    runtime.active_reset_count += 1;
    defer runtime.active_reset_count -= 1;
    var frame = try ResetFrame(PromptType).init(runtime, prompt, body);
    defer frame.deinit();
    frame.setup();
    defineResetFrameStart(PromptType);
    return DriveFrameOutAnswer(PromptType).run(&frame);
}


/// Capture the nearest active delimiter identified by `prompt`.
pub fn shift(
    comptime Resume: type,
    comptime PromptType: type,
    prompt: *const PromptType,
    comptime Handler: type,
) ControlError(PromptType.ErrorSet)!Resume {
    comptime assertHandlerProtocol(Resume, PromptType, Handler);
    const runtime = tls_runtime orelse return error.MissingPrompt;
    try runtime.ensureEnteredRuntime();

    const current_fiber = tls_current_fiber orelse return error.MissingPrompt;
    const wanted_prompt = prompt.token;
    if (current_fiber.prompt_token == wanted_prompt) {
        return shiftLocal(Resume, PromptType, Handler, current_fiber);
    }
    var target_fiber = current_fiber;
    while (target_fiber.prompt_token != wanted_prompt) {
        target_fiber = target_fiber.parent_fiber orelse return error.MissingPrompt;
    }

    const frame: *ResetFrame(PromptType) = @fieldParentPtr("base", target_fiber);
    var capture = ShiftCapture(Resume, PromptType, Handler){
        .base = .{
            .invokeFn = ShiftCapture(Resume, PromptType, Handler).invoke,
            .source_fiber = current_fiber,
            .target_fiber = target_fiber,
        },
        .target_frame = frame,
    };
    current_fiber.state = .suspended;
    current_fiber.outcome = .{ .captured = &capture.base };
    tls_current_fiber = current_fiber.parent_fiber;
    shift_swap_context(&current_fiber.context, current_fiber.parent_context);
    switch (capture.disposition) {
        .resumed => return capture.resume_value.?,
        .pending => unreachable,
    }
}

fn shiftLocal(
    comptime Resume: type,
    comptime PromptType: type,
    comptime Handler: type,
    current_fiber: *FiberBase,
) ControlError(PromptType.ErrorSet)!Resume {
    const frame: *ResetFrame(PromptType) = @fieldParentPtr("base", current_fiber);
    var capture = ShiftCapture(Resume, PromptType, Handler){
        .base = .{
            .invokeFn = ShiftCapture(Resume, PromptType, Handler).invoke,
            .source_fiber = current_fiber,
            .target_fiber = current_fiber,
        },
        .target_frame = frame,
    };
    current_fiber.state = .suspended;
    current_fiber.outcome = .{ .captured = &capture.base };
    tls_current_fiber = current_fiber.parent_fiber;
    shift_swap_context(&current_fiber.context, current_fiber.parent_context);
    switch (capture.disposition) {
        .resumed => return capture.resume_value.?,
        .pending => unreachable,
    }
}

/// Capture the current prompt-local delimiter and resume it once with `resume_value`, preserving the resumed answer.
pub fn shiftLocalIdentity(
    comptime Resume: type,
    comptime PromptType: type,
    prompt: *const PromptType,
    resume_value: Resume,
) ControlError(PromptType.ErrorSet)!Resume {
    if (comptime PromptType.mode != .resume_then_transform) {
        @compileError("shiftLocalIdentity requires PromptMode.resume_then_transform");
    }

    const runtime = tls_runtime orelse return error.MissingPrompt;
    try runtime.ensureEnteredRuntime();

    const current_fiber = tls_current_fiber orelse return error.MissingPrompt;
    if (current_fiber.prompt_token != prompt.token) return error.MissingPrompt;
    return resume_value;
}

test "no-capture reset runs on a fresh runtime" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const NoError = error{};
    const DemoPrompt = Prompt(.resume_then_transform, usize, usize, NoError);
    var prompt = DemoPrompt.init();
    const answer = try reset(DemoPrompt, &runtime, &prompt, struct {
        fn body() ResetError(NoError)!usize {
            return 7;
        }
    }.body);

    try std.testing.expectEqual(@as(usize, 7), answer);
}

test "copied prompt preserves its instance identity" {
    const NoError = error{};
    const DemoPrompt = Prompt(.resume_then_transform, void, void, NoError);
    const original = DemoPrompt.init();
    const copied = original;
    try std.testing.expectEqual(original.token, copied.token);
}

test "distinct prompt values of the same prompt type have distinct identities" {
    const NoError = error{};
    const DemoPrompt = Prompt(.resume_then_transform, void, void, NoError);
    const first = DemoPrompt.init();
    const second = DemoPrompt.init();
    try std.testing.expect(first.token != second.token);
}

test "resume-then-transform handler resumes with a direct-style value" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const NoError = error{};
    const DemoPrompt = Prompt(.resume_then_transform, i32, i32, NoError);
    var prompt = DemoPrompt.init();
    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var resumed_value: i32 = 0;

        const handle = struct {
            /// Supply the resumed value to the suspended body.
            pub fn resumeValue() i32 {
                resumed_value = 41;
                return resumed_value;
            }

            /// Preserve the resumed answer in the enclosing answer type.
            pub fn afterResume(value: i32) i32 {
                return value;
            }
        };

        fn body() ResetError(NoError)!i32 {
            const current = try shift(i32, DemoPrompt, prompt_ptr.?, handle);
            return current + 1;
        }
    };

    demo.prompt_ptr = &prompt;
    const answer = try reset(DemoPrompt, &runtime, &prompt, demo.body);
    try std.testing.expectEqual(@as(i32, 42), answer);
    try std.testing.expectEqual(@as(i32, 41), demo.resumed_value);
}

test "resume-or-return handler may return immediately without resuming" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const NoError = error{};
    const DemoPrompt = Prompt(.resume_or_return, usize, usize, NoError);
    const Decision = ResumeOrReturn(usize, usize);
    var prompt = DemoPrompt.init();
    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;

        const handle = struct {
            /// Choose the immediate return branch for the optional-resumption mode.
            pub fn resumeOrReturn() Decision {
                return Decision.returnNow(99);
            }

            fn afterResume(value: usize) usize {
                return value;
            }
        };

        fn body() ResetError(NoError)!usize {
            _ = try shift(usize, DemoPrompt, prompt_ptr.?, handle);
            return 7;
        }
    };

    demo.prompt_ptr = &prompt;
    const answer = try reset(DemoPrompt, &runtime, &prompt, demo.body);
    try std.testing.expectEqual(@as(usize, 99), answer);
}

test "resume-or-return handler may resume once and transform the resumed answer" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const NoError = error{};
    const DemoPrompt = Prompt(.resume_or_return, i32, i32, NoError);
    const Decision = ResumeOrReturn(i32, i32);
    var prompt = DemoPrompt.init();
    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var resumed_value: i32 = 0;

        const handle = struct {
            /// Choose the resumptive branch for the optional-resumption mode.
            pub fn resumeOrReturn() Decision {
                resumed_value = 41;
                return Decision.resumeWith(resumed_value);
            }

            fn afterResume(value: i32) i32 {
                return value;
            }
        };

        fn body() ResetError(NoError)!i32 {
            const current = try shift(i32, DemoPrompt, prompt_ptr.?, handle);
            return current + 1;
        }
    };

    demo.prompt_ptr = &prompt;
    const answer = try reset(DemoPrompt, &runtime, &prompt, demo.body);
    try std.testing.expectEqual(@as(i32, 42), answer);
    try std.testing.expectEqual(@as(i32, 41), demo.resumed_value);
}

test "resume-or-return handler may propagate typed user errors" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const DemoError = error{Boom};
    const DemoPrompt = Prompt(.resume_or_return, i32, i32, DemoError);
    const Decision = ResumeOrReturn(i32, i32);
    var prompt = DemoPrompt.init();
    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;

        const handle = struct {
            /// Choose the resumptive branch and preserve typed error propagation.
            pub fn resumeOrReturn() ResetError(DemoError)!Decision {
                return Decision.resumeWith(41);
            }

            fn afterResume(_: i32) ResetError(DemoError)!i32 {
                return error.Boom;
            }
        };

        fn body() ResetError(DemoError)!i32 {
            return try shift(i32, DemoPrompt, prompt_ptr.?, handle);
        }
    };

    demo.prompt_ptr = &prompt;
    try std.testing.expectError(error.Boom, reset(DemoPrompt, &runtime, &prompt, demo.body));
}

test "direct-return handler may produce the enclosing answer without resuming" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const NoError = error{};
    const DemoPrompt = Prompt(.direct_return, usize, usize, NoError);
    var prompt = DemoPrompt.init();
    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;

        const handle = struct {
            /// Return the enclosing answer directly from the handler.
            pub fn directReturn() usize {
                return 99;
            }
        };

        fn body() ResetError(NoError)!usize {
            _ = try shift(void, DemoPrompt, prompt_ptr.?, handle);
            return 7;
        }
    };

    demo.prompt_ptr = &prompt;
    const answer = try reset(DemoPrompt, &runtime, &prompt, demo.body);
    try std.testing.expectEqual(@as(usize, 99), answer);
}

test "resume-then-transform handler may propagate typed user errors" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const DemoError = error{Boom};
    const DemoPrompt = Prompt(.resume_then_transform, i32, i32, DemoError);
    var prompt = DemoPrompt.init();
    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;

        const handle = struct {
            /// Raise a user error before resuming to prove the protocol preserves typed errors.
            pub fn resumeValue() ResetError(DemoError)!i32 {
                return error.Boom;
            }

            /// Preserve the resumed answer when the error path is not taken.
            pub fn afterResume(value: i32) ResetError(DemoError)!i32 {
                return value;
            }
        };

        fn body() ResetError(DemoError)!i32 {
            return try shift(i32, DemoPrompt, prompt_ptr.?, handle);
        }
    };

    demo.prompt_ptr = &prompt;
    try std.testing.expectError(error.Boom, reset(DemoPrompt, &runtime, &prompt, demo.body));
}

test "runtime checked deinit rejects active reset" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const TestHelperError = error{ TestExpectedError, TestUnexpectedError };
    const DemoPrompt = Prompt(.resume_then_transform, usize, usize, TestHelperError);
    var prompt = DemoPrompt.init();
    const demo = struct {
        var runtime_ptr: *Runtime = undefined;

        fn body() ResetError(TestHelperError)!usize {
            try std.testing.expectError(error.RuntimeBusy, runtime_ptr.deinitChecked());
            return 7;
        }
    };

    demo.runtime_ptr = &runtime;
    const answer = try reset(DemoPrompt, &runtime, &prompt, demo.body);
    try std.testing.expectEqual(@as(usize, 7), answer);
}

test "runtime checked deinit rejects double teardown and later reset use" {
    var runtime = Runtime.init(std.testing.allocator, .{});

    try runtime.deinitChecked();
    try std.testing.expectError(error.RuntimeDestroyed, runtime.deinitChecked());

    const NoError = error{};
    const DemoPrompt = Prompt(.resume_then_transform, usize, usize, NoError);
    var prompt = DemoPrompt.init();
    try std.testing.expectError(error.RuntimeDestroyed, reset(DemoPrompt, &runtime, &prompt, struct {
        fn body() ResetError(NoError)!usize {
            return 7;
        }
    }.body));
}

test "outer prompt capture bubbles through nested resets" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const NoError = error{};
    const OuterPrompt = Prompt(.resume_then_transform, i32, i32, NoError);
    const InnerPrompt = Prompt(.resume_then_transform, i32, i32, NoError);
    var outer_prompt = OuterPrompt.init();
    var inner_prompt = InnerPrompt.init();
    const demo = struct {
        var outer_prompt_ptr: ?*const OuterPrompt = null;
        var inner_prompt_ptr: ?*const InnerPrompt = null;
        var runtime_ptr: *Runtime = undefined;
        var resumed_value: i32 = 0;

        const outer_handle = struct {
            /// Supply the resumed value to the outer prompt.
            pub fn resumeValue() i32 {
                resumed_value = 41;
                return resumed_value;
            }

            /// Preserve the resumed answer through the outer handler.
            pub fn afterResume(value: i32) i32 {
                return value;
            }
        };

        fn innerBody() ResetError(NoError)!i32 {
            const current = try shift(i32, OuterPrompt, outer_prompt_ptr.?, outer_handle);
            return current + 1;
        }

        fn outerBody() ResetError(NoError)!i32 {
            return try reset(InnerPrompt, runtime_ptr, inner_prompt_ptr.?, innerBody);
        }
    };

    demo.runtime_ptr = &runtime;
    demo.outer_prompt_ptr = &outer_prompt;
    demo.inner_prompt_ptr = &inner_prompt;
    const answer = try reset(OuterPrompt, &runtime, &outer_prompt, demo.outerBody);
    try std.testing.expectEqual(@as(i32, 42), answer);
    try std.testing.expectEqual(@as(i32, 41), demo.resumed_value);
}

test "resume-or-return return-now unwinds nested resets before returning" {
    var runtime = Runtime.init(std.testing.allocator, .{});

    const NoError = error{};
    const OuterPrompt = Prompt(.resume_or_return, []const u8, []const u8, NoError);
    const OuterDecision = ResumeOrReturn(void, []const u8);
    const InnerPrompt = Prompt(.resume_then_transform, void, void, NoError);
    var outer_prompt = OuterPrompt.init();
    var inner_prompt = InnerPrompt.init();
    const demo = struct {
        var outer_prompt_ptr: ?*const OuterPrompt = null;
        var inner_prompt_ptr: ?*const InnerPrompt = null;
        var runtime_ptr: *Runtime = undefined;

        const outer_handle = struct {
            /// Choose the abortive branch after an inner reset captures the outer prompt.
            pub fn resumeOrReturn() OuterDecision {
                return OuterDecision.returnNow("result=early");
            }

            /// Preserve the outer body answer if the resumptive branch were ever taken.
            pub fn afterResume(_: []const u8) []const u8 {
                return "result=late";
            }
        };

        fn innerBody() ResetError(NoError)!void {
            _ = try shift(void, OuterPrompt, outer_prompt_ptr.?, outer_handle);
        }

        fn outerBody() ResetError(NoError)![]const u8 {
            try reset(InnerPrompt, runtime_ptr, inner_prompt_ptr.?, innerBody);
            return "result=late";
        }
    };

    demo.runtime_ptr = &runtime;
    demo.outer_prompt_ptr = &outer_prompt;
    demo.inner_prompt_ptr = &inner_prompt;

    const answer = try reset(OuterPrompt, &runtime, &outer_prompt, demo.outerBody);
    try std.testing.expectEqualStrings("result=early", answer);
    try runtime.deinitChecked();
}

test "unsupported non-diagonal prompt still fails closed on direct completion" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const NoError = error{};
    const DemoPrompt = Prompt(.resume_then_transform, i32, []const u8, NoError);
    var prompt = DemoPrompt.init();

    try std.testing.expectError(error.NonDiagonalComplete, reset(DemoPrompt, &runtime, &prompt, struct {
        fn body() ResetError(NoError)!i32 {
            return 7;
        }
    }.body));
}
