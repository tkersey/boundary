const builtin = @import("builtin");
const std = @import("std");

/// Runtime errors surfaced by the fiber-backed control core.
pub const Error = error{
    AlreadyResolved,
    CrossThread,
    MissingPrompt,
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

/// Thread-affine runtime that owns stackful continuations.
pub const Runtime = struct {
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

    /// Fixed runtime defaults for the experimental stackful backend.
    pub const Options = struct {
        stack_bytes: usize = 256 * 1024,
        guard_pages: usize = 1,
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
        const guard_bytes = options.guard_pages * page_size;
        const total = options.stack_bytes + guard_bytes;
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
pub fn Prompt(comptime AnswerType: type, comptime ErrorSetType: type) type {
    return struct {
        /// Answer type for computations delimited by this prompt value.
        pub const Answer = AnswerType;
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
    startFn: *const fn (*FiberBase) noreturn,
};

const CaptureBase = struct {
    invokeFn: *const fn (*CaptureBase, *anyopaque) anyerror!void,
    target_fiber: *FiberBase,
};

fn ResetFrame(comptime PromptType: type) type {
    const Answer = PromptType.Answer;
    const ErrorSet = PromptType.ErrorSet;
    return struct {
        base: FiberBase,
        body: *const fn () ResetError(ErrorSet)!Answer,
        result: union(enum) {
            answer: Answer,
            err: ResetError(ErrorSet),
            none,
        } = .none,

        fn init(runtime: *Runtime, prompt: *const PromptType, body: *const fn () ResetError(ErrorSet)!Answer) ResetError(ErrorSet)!@This() {
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

fn finishCurrentFiberWithAnswer(comptime PromptType: type, frame: *ResetFrame(PromptType), answer: PromptType.Answer) noreturn {
    frame.result = .{ .answer = answer };
    frame.base.state = .done;
    frame.base.outcome = .none;
    tls_current_fiber = frame.base.parent_fiber;
    shift_swap_context(&frame.base.context, frame.base.parent_context);
    unreachable;
}

fn finishCurrentFiberWithError(comptime PromptType: type, frame: *ResetFrame(PromptType), err: ResetError(PromptType.ErrorSet)) noreturn {
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

fn DriveFrame(comptime PromptType: type) type {
    const Answer = PromptType.Answer;
    const ErrorSet = PromptType.ErrorSet;
    return struct {
        fn run(frame: *ResetFrame(PromptType)) ResetError(ErrorSet)!Answer {
            const runtime = frame.base.runtime;
            try runtime.ensureThread();
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
                        .answer => |answer| return answer,
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
                            var answer: ?Answer = null;
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

/// One-shot continuation handle for a captured `shift`.
pub fn Continuation(comptime Resume: type, comptime PromptType: type) type {
    const Answer = PromptType.Answer;
    const ErrorSet = PromptType.ErrorSet;
    const Capture = ShiftCapture(Resume, PromptType);
    return struct {
        capture: *Capture,

        /// Resume the captured continuation once with `value`.
        pub fn resumeWith(self: *@This(), value: Resume) ResetError(ErrorSet)!Answer {
            if (self.capture.consumed) return error.AlreadyResolved;
            self.capture.consumed = true;
            self.capture.disposition = .resumed;
            self.capture.resume_value = value;
            return DriveFrame(PromptType).run(self.capture.target_frame);
        }
    };
}

fn ShiftCapture(comptime Resume: type, comptime PromptType: type) type {
    const Answer = PromptType.Answer;
    const ErrorSet = PromptType.ErrorSet;
    return struct {
        base: CaptureBase,
        target_frame: *ResetFrame(PromptType),
        handler: *const fn (*Continuation(Resume, PromptType)) ResetError(ErrorSet)!Answer,
        consumed: bool = false,
        disposition: enum {
            pending,
            resumed,
        } = .pending,
        resume_value: ?Resume = null,

        fn invoke(base: *CaptureBase, answer_out: *anyopaque) anyerror!void {
            const self: *@This() = @fieldParentPtr("base", base);
            var continuation = Continuation(Resume, PromptType){ .capture = self };
            const answer = self.handler(&continuation) catch |err| return err;
            const out: *?Answer = @ptrCast(@alignCast(answer_out));
            out.* = answer;
        }
    };
}

/// Run `body` under a fresh delimiter identified by `prompt`.
pub fn reset(
    comptime PromptType: type,
    runtime: *Runtime,
    prompt: *const PromptType,
    body: *const fn () ResetError(PromptType.ErrorSet)!PromptType.Answer,
) ResetError(PromptType.ErrorSet)!PromptType.Answer {
    try runtime.ensureThread();
    runtime.active_reset_count += 1;
    defer runtime.active_reset_count -= 1;
    var frame = try ResetFrame(PromptType).init(runtime, prompt, body);
    defer frame.deinit();
    frame.setup();
    defineResetFrameStart(PromptType);
    return DriveFrame(PromptType).run(&frame);
}

/// Capture the nearest active delimiter identified by `prompt`.
pub fn shift(
    comptime Resume: type,
    comptime PromptType: type,
    prompt: *const PromptType,
    handler: *const fn (*Continuation(Resume, PromptType)) ResetError(PromptType.ErrorSet)!PromptType.Answer,
) ControlError(PromptType.ErrorSet)!Resume {
    const runtime = tls_runtime orelse return error.MissingPrompt;
    try runtime.ensureThread();

    const current_fiber = tls_current_fiber orelse return error.MissingPrompt;
    const wanted_prompt = prompt.token;
    var target_fiber = current_fiber;
    while (target_fiber.prompt_token != wanted_prompt) {
        target_fiber = target_fiber.parent_fiber orelse return error.MissingPrompt;
    }

    const frame: *ResetFrame(PromptType) = @fieldParentPtr("base", target_fiber);
    var capture = ShiftCapture(Resume, PromptType){
        .base = .{
            .invokeFn = ShiftCapture(Resume, PromptType).invoke,
            .target_fiber = target_fiber,
        },
        .target_frame = frame,
        .handler = handler,
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

test "no-capture reset runs on a fresh runtime" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const NoError = error{};
    const DemoPrompt = Prompt(usize, NoError);
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
    const DemoPrompt = Prompt(void, NoError);
    const original = DemoPrompt.init();
    const copied = original;
    try std.testing.expectEqual(original.token, copied.token);
}

test "distinct prompt values of the same prompt type have distinct identities" {
    const NoError = error{};
    const DemoPrompt = Prompt(void, NoError);
    const first = DemoPrompt.init();
    const second = DemoPrompt.init();
    try std.testing.expect(first.token != second.token);
}

test "shift resumes with a direct-style value" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const NoError = error{};
    const DemoPrompt = Prompt(i32, NoError);
    var prompt = DemoPrompt.init();
    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var resumed_value: i32 = 0;

        fn handle(k: *Continuation(i32, DemoPrompt)) ResetError(NoError)!i32 {
            resumed_value = 41;
            return try k.resumeWith(resumed_value);
        }

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

test "continuation is strictly one-shot" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const TestHelperError = error{ TestExpectedError, TestUnexpectedError };
    const DemoPrompt = Prompt(void, TestHelperError);
    var prompt = DemoPrompt.init();
    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;

        fn handle(k: *Continuation(void, DemoPrompt)) ResetError(TestHelperError)!void {
            try k.resumeWith({});
            try std.testing.expectError(error.AlreadyResolved, k.resumeWith({}));
        }

        fn body() ResetError(TestHelperError)!void {
            _ = try shift(void, DemoPrompt, prompt_ptr.?, handle);
        }
    };

    demo.prompt_ptr = &prompt;
    try reset(DemoPrompt, &runtime, &prompt, demo.body);
}

test "handler may return the enclosing answer without resuming" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const NoError = error{};
    const DemoPrompt = Prompt(usize, NoError);
    var prompt = DemoPrompt.init();
    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;

        fn handle(_: *Continuation(void, DemoPrompt)) ResetError(NoError)!usize {
            return 99;
        }

        fn body() ResetError(NoError)!usize {
            _ = try shift(void, DemoPrompt, prompt_ptr.?, handle);
            return 7;
        }
    };

    demo.prompt_ptr = &prompt;
    const answer = try reset(DemoPrompt, &runtime, &prompt, demo.body);
    try std.testing.expectEqual(@as(usize, 99), answer);
}

test "runtime checked deinit rejects active reset" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const TestHelperError = error{ TestExpectedError, TestUnexpectedError };
    const DemoPrompt = Prompt(usize, TestHelperError);
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
    const DemoPrompt = Prompt(usize, NoError);
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
    const OuterPrompt = Prompt(i32, NoError);
    const InnerPrompt = Prompt(i32, NoError);
    var outer_prompt = OuterPrompt.init();
    var inner_prompt = InnerPrompt.init();
    const demo = struct {
        var outer_prompt_ptr: ?*const OuterPrompt = null;
        var inner_prompt_ptr: ?*const InnerPrompt = null;
        var runtime_ptr: *Runtime = undefined;
        var resumed_value: i32 = 0;

        fn outerHandle(k: *Continuation(i32, OuterPrompt)) ResetError(NoError)!i32 {
            resumed_value = 41;
            return try k.resumeWith(resumed_value);
        }

        fn innerBody() ResetError(NoError)!i32 {
            const current = try shift(i32, OuterPrompt, outer_prompt_ptr.?, outerHandle);
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
