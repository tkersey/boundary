const builtin = @import("builtin");
const std = @import("std");

/// Runtime errors surfaced by the fiber-backed control core.
pub const Error = error{
    AlreadyResolved,
    ContinuationNotConsumed,
    CrossThread,
    MissingPrompt,
    RuntimeBusy,
    RuntimeDestroyed,
    ShiftForbidden,
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
    no_shift_depth: usize = 0,
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
        if (self.active_reset_count != 0 or self.no_shift_depth != 0) return error.RuntimeBusy;
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

/// Region guard that forbids `shift` while unsafe work is active.
pub const NoShiftGuard = struct {
    runtime: ?*Runtime,

    /// Mark the current thread as unable to suspend until `leave`.
    pub fn enter(runtime: *Runtime) Error!NoShiftGuard {
        try runtime.ensureThread();
        runtime.no_shift_depth += 1;
        return .{ .runtime = runtime };
    }

    /// Leave a previously-entered no-shift region.
    pub fn leave(self: *NoShiftGuard) void {
        self.leaveChecked() catch |err| switch (err) {
            error.AlreadyResolved, error.CrossThread => unreachable,
            else => unreachable,
        };
    }

    /// Leave a previously-entered no-shift region, returning an error on misuse.
    pub fn leaveChecked(self: *NoShiftGuard) Error!void {
        if (self.runtime) |runtime| {
            try runtime.ensureThread();
            runtime.no_shift_depth -= 1;
            self.runtime = null;
            return;
        }
        return error.AlreadyResolved;
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

const PromptToken = *const anyopaque;

fn PromptTokenMarker(comptime Tag: type) type {
    return struct {
        const _tag = Tag;
        var marker: u8 = 0;
    };
}

fn promptToken(comptime Tag: type) PromptToken {
    return @ptrCast(&PromptTokenMarker(Tag).marker);
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

fn ResetFrame(comptime Tag: type, comptime Answer: type, comptime ErrorSet: type) type {
    return struct {
        base: FiberBase,
        body: *const fn () ResetError(ErrorSet)!Answer,
        result: union(enum) {
            answer: Answer,
            err: ResetError(ErrorSet),
            none,
        } = .none,

        fn init(runtime: *Runtime, body: *const fn () ResetError(ErrorSet)!Answer) ResetError(ErrorSet)!@This() {
            const parent_fiber = tls_current_fiber;
            const parent_context = if (parent_fiber) |fiber| &fiber.context else &runtime.root_context;
            const stack = try runtime.acquireStack();
            return .{
                .base = .{
                    .runtime = runtime,
                    .parent_fiber = parent_fiber,
                    .parent_context = parent_context,
                    .stack = stack,
                    .prompt_token = promptToken(Tag),
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
            const answer = self.body() catch |err| finishCurrentFiberWithError(Tag, Answer, ErrorSet, self, err);
            finishCurrentFiberWithAnswer(Tag, Answer, ErrorSet, self, answer);
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

fn finishCurrentFiberWithAnswer(comptime Tag: type, comptime Answer: type, comptime ErrorSet: type, frame: *ResetFrame(Tag, Answer, ErrorSet), answer: Answer) noreturn {
    frame.result = .{ .answer = answer };
    frame.base.state = .done;
    frame.base.outcome = .none;
    tls_current_fiber = frame.base.parent_fiber;
    shift_swap_context(&frame.base.context, frame.base.parent_context);
    unreachable;
}

fn finishCurrentFiberWithError(comptime Tag: type, comptime Answer: type, comptime ErrorSet: type, frame: *ResetFrame(Tag, Answer, ErrorSet), err: ResetError(ErrorSet)) noreturn {
    frame.result = .{ .err = err };
    frame.base.state = .failed;
    frame.base.outcome = .none;
    tls_current_fiber = frame.base.parent_fiber;
    shift_swap_context(&frame.base.context, frame.base.parent_context);
    unreachable;
}

fn defineResetFrameStart(comptime Tag: type, comptime Answer: type, comptime ErrorSet: type) void {
    _ = Tag;
    _ = Answer;
    _ = ErrorSet;
}

fn DriveFrame(comptime Tag: type, comptime Answer: type, comptime ErrorSet: type) type {
    return struct {
        fn run(frame: *ResetFrame(Tag, Answer, ErrorSet)) ResetError(ErrorSet)!Answer {
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
pub fn Continuation(comptime Resume: type, comptime Tag: type, comptime Answer: type, comptime ErrorSet: type) type {
    const Capture = ShiftCapture(Resume, Tag, Answer, ErrorSet);
    return struct {
        capture: *Capture,

        /// Resume the captured continuation once with `value`.
        pub fn resumeWith(self: *@This(), value: Resume) ResetError(ErrorSet)!Answer {
            if (self.capture.consumed) return error.AlreadyResolved;
            self.capture.consumed = true;
            self.capture.disposition = .resumed;
            self.capture.resume_value = value;
            return DriveFrame(Tag, Answer, ErrorSet).run(self.capture.target_frame);
        }

        /// Discontinue the captured continuation with `err`.
        pub fn discontinue(self: *@This(), err: ErrorSet) ResetError(ErrorSet)!Answer {
            if (self.capture.consumed) return error.AlreadyResolved;
            self.capture.consumed = true;
            self.capture.disposition = .discontinued;
            self.capture.discontinue_error = err;
            return DriveFrame(Tag, Answer, ErrorSet).run(self.capture.target_frame);
        }
    };
}

fn ShiftCapture(comptime Resume: type, comptime Tag: type, comptime Answer: type, comptime ErrorSet: type) type {
    return struct {
        base: CaptureBase,
        target_frame: *ResetFrame(Tag, Answer, ErrorSet),
        handler: *const fn (*Continuation(Resume, Tag, Answer, ErrorSet)) ResetError(ErrorSet)!Answer,
        consumed: bool = false,
        disposition: enum {
            discontinued,
            pending,
            resumed,
        } = .pending,
        resume_value: ?Resume = null,
        discontinue_error: ?ErrorSet = null,

            fn invoke(base: *CaptureBase, answer_out: *anyopaque) anyerror!void {
            const self: *@This() = @fieldParentPtr("base", base);
            var continuation = Continuation(Resume, Tag, Answer, ErrorSet){ .capture = self };
            const answer = self.handler(&continuation) catch |err| return err;
            if (!self.consumed) return error.ContinuationNotConsumed;
            const out: *?Answer = @ptrCast(@alignCast(answer_out));
            out.* = answer;
        }
    };
}

/// Run `body` under a fresh delimiter tagged by `Tag`.
pub fn reset(
    comptime Tag: type,
    comptime Answer: type,
    comptime ErrorSet: type,
    runtime: *Runtime,
    body: *const fn () ResetError(ErrorSet)!Answer,
) ResetError(ErrorSet)!Answer {
    try runtime.ensureThread();
    runtime.active_reset_count += 1;
    defer runtime.active_reset_count -= 1;
    var frame = try ResetFrame(Tag, Answer, ErrorSet).init(runtime, body);
    defer frame.deinit();
    frame.setup();
    defineResetFrameStart(Tag, Answer, ErrorSet);
    return DriveFrame(Tag, Answer, ErrorSet).run(&frame);
}

/// Capture the nearest active delimiter tagged by `Tag`.
pub fn shift(
    comptime Resume: type,
    comptime Tag: type,
    comptime Answer: type,
    comptime ErrorSet: type,
    handler: *const fn (*Continuation(Resume, Tag, Answer, ErrorSet)) ResetError(ErrorSet)!Answer,
) ControlError(ErrorSet)!Resume {
    const runtime = tls_runtime orelse return error.MissingPrompt;
    try runtime.ensureThread();
    if (runtime.no_shift_depth != 0) return error.ShiftForbidden;

    const current_fiber = tls_current_fiber orelse return error.MissingPrompt;
    const wanted_prompt = promptToken(Tag);
    var target_fiber = current_fiber;
    while (target_fiber.prompt_token != wanted_prompt) {
        target_fiber = target_fiber.parent_fiber orelse return error.MissingPrompt;
    }

    const frame: *ResetFrame(Tag, Answer, ErrorSet) = @fieldParentPtr("base", target_fiber);
    var capture = ShiftCapture(Resume, Tag, Answer, ErrorSet){
        .base = .{
            .invokeFn = ShiftCapture(Resume, Tag, Answer, ErrorSet).invoke,
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
        .discontinued => return capture.discontinue_error.?,
        .pending => unreachable,
    }
}

test "no-capture reset runs on a fresh runtime" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const tag = struct {};
    const NoError = error{};
    const answer = try reset(tag, usize, NoError, &runtime, struct {
        fn body() ResetError(NoError)!usize {
            return 7;
        }
    }.body);

    try std.testing.expectEqual(@as(usize, 7), answer);
}

test "prompt token stays stable for the same tag type" {
    const tag = struct {};
    try std.testing.expectEqual(
        @intFromPtr(promptToken(tag)),
        @intFromPtr(promptToken(tag)),
    );
}

test "prompt token differs for distinct tag types" {
    const tag_a = struct {};
    const tag_b = struct {};
    try std.testing.expect(
        @intFromPtr(promptToken(tag_a)) != @intFromPtr(promptToken(tag_b)),
    );
}

test "prompt token differs across local namespaces" {
    const scope_a = struct {
        const tag = struct {};
    };
    const scope_b = struct {
        const tag = struct {};
    };
    try std.testing.expect(
        @intFromPtr(promptToken(scope_a.tag)) != @intFromPtr(promptToken(scope_b.tag)),
    );
}

test "shift resumes with a direct-style value" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const tag = struct {};
    const NoError = error{};
    const demo = struct {
        var resumed_value: i32 = 0;

        fn handle(k: *Continuation(i32, tag, i32, NoError)) ResetError(NoError)!i32 {
            resumed_value = 41;
            return try k.resumeWith(resumed_value);
        }

        fn body() ResetError(NoError)!i32 {
            const current = try shift(i32, tag, i32, NoError, handle);
            return current + 1;
        }
    };

    const answer = try reset(tag, i32, NoError, &runtime, demo.body);
    try std.testing.expectEqual(@as(i32, 42), answer);
    try std.testing.expectEqual(@as(i32, 41), demo.resumed_value);
}

test "discontinue returns the injected error" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const tag = struct {};
    const DemoError = error{Stop};
    const demo = struct {
        fn handle(k: *Continuation(void, tag, usize, DemoError)) ResetError(DemoError)!usize {
            return k.discontinue(error.Stop);
        }

        fn body() ResetError(DemoError)!usize {
            _ = try shift(void, tag, usize, DemoError, handle);
            return 99;
        }
    };

    try std.testing.expectError(error.Stop, reset(tag, usize, DemoError, &runtime, demo.body));
}

test "continuation is strictly one-shot" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const tag = struct {};
    const TestHelperError = error{ TestExpectedError, TestUnexpectedError };
    const demo = struct {
        fn handle(k: *Continuation(void, tag, void, TestHelperError)) ResetError(TestHelperError)!void {
            try k.resumeWith({});
            try std.testing.expectError(error.AlreadyResolved, k.resumeWith({}));
        }

        fn body() ResetError(TestHelperError)!void {
            _ = try shift(void, tag, void, TestHelperError, handle);
        }
    };

    try reset(tag, void, TestHelperError, &runtime, demo.body);
}

test "no-shift guard rejects capture" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const tag = struct {};
    const NoError = error{};
    const demo = struct {
        var runtime_ptr: *Runtime = undefined;

        fn handle(_: *Continuation(void, tag, void, NoError)) ResetError(NoError)!void {
            unreachable;
        }

        fn body() ResetError(NoError)!void {
            var guard = try NoShiftGuard.enter(runtime_ptr);
            defer guard.leave();
            _ = try shift(void, tag, void, NoError, handle);
        }
    };

    demo.runtime_ptr = &runtime;
    try std.testing.expectError(error.ShiftForbidden, reset(tag, void, NoError, &runtime, demo.body));
}

test "no-shift guard checked leave rejects cross-thread use" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    var guard = try NoShiftGuard.enter(&runtime);
    var attempt = struct {
        guard: NoShiftGuard,
        result: ?Error = null,

        fn run(self: *@This()) void {
            self.guard.leaveChecked() catch |err| {
                self.result = err;
                return;
            };
        }
    }{
        .guard = guard,
    };

    var thread = try std.Thread.spawn(.{}, @TypeOf(attempt).run, .{&attempt});
    thread.join();
    try std.testing.expectEqual(error.CrossThread, attempt.result.?);
    try guard.leaveChecked();
}

test "runtime checked deinit rejects active reset" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const tag = struct {};
    const TestHelperError = error{ TestExpectedError, TestUnexpectedError };
    const demo = struct {
        var runtime_ptr: *Runtime = undefined;

        fn body() ResetError(TestHelperError)!usize {
            try std.testing.expectError(error.RuntimeBusy, runtime_ptr.deinitChecked());
            return 7;
        }
    };

    demo.runtime_ptr = &runtime;
    const answer = try reset(tag, usize, TestHelperError, &runtime, demo.body);
    try std.testing.expectEqual(@as(usize, 7), answer);
}

test "runtime checked deinit rejects double teardown and later reset use" {
    var runtime = Runtime.init(std.testing.allocator, .{});

    try runtime.deinitChecked();
    try std.testing.expectError(error.RuntimeDestroyed, runtime.deinitChecked());

    const tag = struct {};
    const NoError = error{};
    try std.testing.expectError(error.RuntimeDestroyed, reset(tag, usize, NoError, &runtime, struct {
        fn body() ResetError(NoError)!usize {
            return 7;
        }
    }.body));
}

test "outer prompt capture bubbles through nested resets" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const outer_tag = struct {};
    const inner_tag = struct {};
    const NoError = error{};
    const demo = struct {
        var runtime_ptr: *Runtime = undefined;
        var resumed_value: i32 = 0;

        fn outerHandle(k: *Continuation(i32, outer_tag, i32, NoError)) ResetError(NoError)!i32 {
            resumed_value = 41;
            return try k.resumeWith(resumed_value);
        }

        fn innerBody() ResetError(NoError)!i32 {
            const current = try shift(i32, outer_tag, i32, NoError, outerHandle);
            return current + 1;
        }

        fn outerBody() ResetError(NoError)!i32 {
            return try reset(inner_tag, i32, NoError, runtime_ptr, innerBody);
        }
    };

    demo.runtime_ptr = &runtime;
    const answer = try reset(outer_tag, i32, NoError, &runtime, demo.outerBody);
    try std.testing.expectEqual(@as(i32, 42), answer);
    try std.testing.expectEqual(@as(i32, 41), demo.resumed_value);
}
