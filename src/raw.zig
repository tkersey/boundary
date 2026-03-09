const builtin = @import("builtin");
const std = @import("std");

/// Runtime errors surfaced by the fiber-backed control core.
pub const Error = error{
    AlreadyResolved,
    CrossThread,
    MissingPrompt,
    OutOfMemory,
    RuntimeAliased,
    RuntimeBusy,
    RuntimeDestroyed,
    ShiftForbidden,
    SuspensionAliased,
};

/// Setup failures that can occur before user code enters `reset`.
pub const SetupError = std.posix.MMapError || std.posix.MProtectError;

/// Runtime-visible error union for user-provided errors.
pub fn ControlError(comptime ErrorSet: type) type {
    return Error || ErrorSet;
}

/// Full `reset`-path error union including setup failures.
pub fn ResetError(comptime ErrorSet: type) type {
    return ControlError(ErrorSet) || SetupError;
}

fn TagOf(comptime Spec: type) type {
    return Spec.tag;
}

fn RequestOf(comptime Spec: type) type {
    return Spec.Request;
}

fn ResumeOf(comptime Spec: type) type {
    return Spec.Resume;
}

fn AnswerOf(comptime Spec: type) type {
    return Spec.Answer;
}

fn ErrorSetOf(comptime Spec: type) type {
    return Spec.ErrorSet;
}

const page_size = std.heap.page_size_min;

const CachedSuspension = struct {
    next: ?*CachedSuspension = null,
    key: usize,
    deinitFn: *const fn (*CachedSuspension, std.mem.Allocator) void,
};

const CachedFrame = struct {
    next: ?*CachedFrame = null,
    key: usize,
    deinitFn: *const fn (*CachedFrame, std.mem.Allocator) void,
};

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

/// Thread-affine runtime that owns stackful continuations.
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    options: Options,
    thread_id: std.Thread.Id,
    owner_cookie: usize = 0,
    state: enum {
        alive,
        destroyed,
    } = .alive,
    root_context: Context = .{},
    active_reset_count: usize = 0,
    active_suspension_count: usize = 0,
    no_shift_depth: usize = 0,
    cached_stacks: std.ArrayList(Stack) = .empty,
    cached_frames: ?*CachedFrame = null,
    cached_suspensions: ?*CachedSuspension = null,

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
        if (self.active_reset_count != 0 or self.active_suspension_count != 0 or self.no_shift_depth != 0) {
            return error.RuntimeBusy;
        }
        while (self.cached_stacks.pop()) |stack| {
            stack.deinit();
        }
        self.cached_stacks.deinit(self.allocator);
        self.cached_stacks = .empty;

        var cached_frame = self.cached_frames;
        while (cached_frame) |node| {
            const next = node.next;
            node.deinitFn(node, self.allocator);
            cached_frame = next;
        }
        self.cached_frames = null;

        var cached_suspension = self.cached_suspensions;
        while (cached_suspension) |node| {
            const next = node.next;
            node.deinitFn(node, self.allocator);
            cached_suspension = next;
        }
        self.cached_suspensions = null;
        self.state = .destroyed;
    }

    fn ensureThread(self: *Runtime) Error!void {
        if (self.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
        if (self.owner_cookie == 0) {
            self.owner_cookie = @intFromPtr(self);
        } else if (self.owner_cookie != @intFromPtr(self)) {
            return error.RuntimeAliased;
        }
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

    fn popCachedSuspension(self: *Runtime, comptime Record: type, key: usize) ?*Record {
        var cursor = &self.cached_suspensions;
        while (cursor.*) |node| {
            if (node.key == key) {
                cursor.* = node.next;
                return @fieldParentPtr("cached", node);
            }
            cursor = &node.next;
        }
        return null;
    }

    fn pushCachedSuspension(self: *Runtime, node: *CachedSuspension) void {
        node.next = self.cached_suspensions;
        self.cached_suspensions = node;
    }

    fn popCachedFrame(self: *Runtime, comptime Frame: type, key: usize) ?*Frame {
        var cursor = &self.cached_frames;
        while (cursor.*) |node| {
            if (node.key == key) {
                cursor.* = node.next;
                return @fieldParentPtr("cached", node);
            }
            cursor = &node.next;
        }
        return null;
    }

    fn pushCachedFrame(self: *Runtime, node: *CachedFrame) void {
        node.next = self.cached_frames;
        self.cached_frames = node;
    }
};

/// Region guard that forbids `shift` while unsafe work is active.
pub const NoShiftGuard = struct {
    runtime: ?*Runtime = null,
    owner_cookie: usize = 0,

    /// Mark the current thread as unable to suspend until `leave`.
    pub fn enter(self: *NoShiftGuard, runtime: *Runtime) Error!void {
        if (self.runtime != null) return error.AlreadyResolved;
        try runtime.ensureThread();
        runtime.no_shift_depth += 1;
        self.runtime = runtime;
        self.owner_cookie = @intFromPtr(self);
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
            if (self.owner_cookie != @intFromPtr(self)) return error.AlreadyResolved;
            runtime.no_shift_depth -= 1;
            self.runtime = null;
            self.owner_cookie = 0;
            return;
        }
        return error.AlreadyResolved;
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
    none,
    suspension: *SuspensionBase,
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

const SuspensionBase = struct {
    target_fiber: *FiberBase,
};

fn ResetFrame(comptime Tag: type, comptime Answer: type, comptime ErrorSet: type) type {
    return struct {
        cached: CachedFrame,
        base: FiberBase,
        body: *const fn () ResetError(ErrorSet)!Answer,
        result: union(enum) {
            answer: Answer,
            err: ResetError(ErrorSet),
            none,
        } = .none,

        fn create(runtime: *Runtime, body: *const fn () ResetError(ErrorSet)!Answer) ResetError(ErrorSet)!*@This() {
            const frame = runtime.popCachedFrame(@This(), frameCacheKey(Tag, Answer, ErrorSet)) orelse try runtime.allocator.create(@This());
            const parent_fiber = tls_current_fiber;
            const parent_context = if (parent_fiber) |fiber| &fiber.context else &runtime.root_context;
            const stack = try runtime.acquireStack();
            frame.* = .{
                .cached = .{
                    .key = frameCacheKey(Tag, Answer, ErrorSet),
                    .deinitFn = freeCached,
                },
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
            frame.setup();
            return frame;
        }

        fn setup(self: *@This()) void {
            initializeContext(&self.base.context, self.base.stack.top());
        }

        fn destroy(self: *@This()) void {
            self.base.runtime.releaseStack(self.base.stack);
            self.base.runtime.pushCachedFrame(&self.cached);
        }

        fn freeCached(node: *CachedFrame, allocator: std.mem.Allocator) void {
            const self: *@This() = @fieldParentPtr("cached", node);
            allocator.destroy(self);
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

fn FrameCacheMarker(comptime Tag: type, comptime Answer: type, comptime ErrorSet: type) type {
    return struct {
        const _tag = Tag;
        const _answer = Answer;
        const _error_set = ErrorSet;
        var marker: u8 = 0;
    };
}

fn frameCacheKey(comptime Tag: type, comptime Answer: type, comptime ErrorSet: type) usize {
    return @intFromPtr(&FrameCacheMarker(Tag, Answer, ErrorSet).marker);
}

fn SuspensionCacheMarker(comptime Spec: type) type {
    return struct {
        const _spec = Spec;
        var marker: u8 = 0;
    };
}

fn suspensionCacheKey(comptime Spec: type) usize {
    return @intFromPtr(&SuspensionCacheMarker(Spec).marker);
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

/// Result of driving a delimiter until completion or suspension.
pub fn Step(comptime Spec: type) type {
    return union(enum) {
        complete: AnswerOf(Spec),
        suspended: Suspension(Spec),
    };
}

/// Escaped one-shot suspension handle for `shift`.
pub fn Suspension(comptime Spec: type) type {
    const Record = SuspensionRecord(Spec);
    return struct {
        request: RequestOf(Spec),
        record: ?*Record,
        generation: usize,

        fn prepare(self: *@This()) Error!*Record {
            const record = self.record orelse return error.AlreadyResolved;
            try record.runtime.ensureThread();
            if (record.generation != self.generation) return error.SuspensionAliased;
            if (record.owner_cookie == 0) {
                record.owner_cookie = @intFromPtr(self);
            } else if (record.owner_cookie != @intFromPtr(self)) {
                return error.SuspensionAliased;
            }
            if (record.state != .pending) return error.AlreadyResolved;
            self.record = null;
            return record;
        }

        /// Resume the escaped one-shot suspension with `value`.
        pub fn resumeWith(self: *@This(), value: ResumeOf(Spec)) ResetError(ErrorSetOf(Spec))!Step(Spec) {
            const record = try self.prepare();
            record.state = .resumed;
            record.resume_value = value;
            record.runtime.active_suspension_count -= 1;
            defer {
                record.owner_cookie = 0;
                record.resume_value = null;
                record.discontinue_error = null;
                record.generation += 1;
                record.runtime.pushCachedSuspension(&record.cached);
            }
            return try driveFrame(Spec, record.target_frame);
        }

        /// Inject `err` into the escaped suspension.
        pub fn discontinue(self: *@This(), err: ErrorSetOf(Spec)) ResetError(ErrorSetOf(Spec))!Step(Spec) {
            const record = try self.prepare();
            record.state = .discontinued;
            record.discontinue_error = err;
            record.runtime.active_suspension_count -= 1;
            defer {
                record.owner_cookie = 0;
                record.resume_value = null;
                record.discontinue_error = null;
                record.generation += 1;
                record.runtime.pushCachedSuspension(&record.cached);
            }
            return try driveFrame(Spec, record.target_frame);
        }
    };
}

fn SuspensionRecord(comptime Spec: type) type {
    return struct {
        base: SuspensionBase,
        cached: CachedSuspension,
        runtime: *Runtime,
        target_frame: *ResetFrame(TagOf(Spec), AnswerOf(Spec), ErrorSetOf(Spec)),
        request: RequestOf(Spec),
        generation: usize = 1,
        owner_cookie: usize = 0,
        state: enum {
            discontinued,
            pending,
            resumed,
        } = .pending,
        resume_value: ?ResumeOf(Spec) = null,
        discontinue_error: ?ErrorSetOf(Spec) = null,

        fn deinitCached(node: *CachedSuspension, allocator: std.mem.Allocator) void {
            const self: *@This() = @fieldParentPtr("cached", node);
            allocator.destroy(self);
        }
    };
}

fn driveFrame(comptime Spec: type, frame: *ResetFrame(TagOf(Spec), AnswerOf(Spec), ErrorSetOf(Spec))) ResetError(ErrorSetOf(Spec))!Step(Spec) {
    const runtime = frame.base.runtime;
    try runtime.ensureThread();
    runtime.active_reset_count += 1;
    defer runtime.active_reset_count -= 1;
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
            .done => {
                const answer = switch (frame.result) {
                    .answer => |value| value,
                    else => unreachable,
                };
                frame.destroy();
                return .{ .complete = answer };
            },
            .failed => {
                const err = switch (frame.result) {
                    .err => |value| value,
                    else => unreachable,
                };
                frame.destroy();
                return err;
            },
            .suspended => switch (frame.base.outcome) {
                .suspension => |base| {
                    if (base.target_fiber != &frame.base) {
                        const active_parent = tls_current_fiber.?;
                        active_parent.state = .suspended;
                        active_parent.outcome = .{ .suspension = base };
                        tls_current_fiber = active_parent.parent_fiber;
                        shift_swap_context(&active_parent.context, active_parent.parent_context);
                        continue;
                    }
                    const record: *SuspensionRecord(Spec) = @fieldParentPtr("base", base);
                    return .{
                        .suspended = .{
                            .request = record.request,
                            .record = record,
                            .generation = record.generation,
                        },
                    };
                },
                else => unreachable,
            },
            else => unreachable,
        }
    }
}

/// Run `body` under a fresh delimiter tagged by `Tag`.
pub fn reset(
    comptime Spec: type,
    runtime: *Runtime,
    body: *const fn () ResetError(ErrorSetOf(Spec))!AnswerOf(Spec),
) ResetError(ErrorSetOf(Spec))!Step(Spec) {
    try runtime.ensureThread();
    const frame = try ResetFrame(TagOf(Spec), AnswerOf(Spec), ErrorSetOf(Spec)).create(runtime, body);
    return try driveFrame(Spec, frame);
}

/// Capture the nearest active delimiter tagged by `Tag`.
pub fn shift(
    comptime Spec: type,
    request: RequestOf(Spec),
) ControlError(ErrorSetOf(Spec))!ResumeOf(Spec) {
    const runtime = tls_runtime orelse return error.MissingPrompt;
    try runtime.ensureThread();
    if (runtime.no_shift_depth != 0) return error.ShiftForbidden;

    const current_fiber = tls_current_fiber orelse return error.MissingPrompt;
    const wanted_prompt = promptToken(TagOf(Spec));
    var target_fiber = current_fiber;
    while (target_fiber.prompt_token != wanted_prompt) {
        target_fiber = target_fiber.parent_fiber orelse return error.MissingPrompt;
    }

    const frame: *ResetFrame(TagOf(Spec), AnswerOf(Spec), ErrorSetOf(Spec)) = @fieldParentPtr("base", target_fiber);
    const record, const generation = blk: {
        if (runtime.popCachedSuspension(SuspensionRecord(Spec), suspensionCacheKey(Spec))) |cached| {
            break :blk .{ cached, cached.generation };
        }
        const fresh = runtime.allocator.create(SuspensionRecord(Spec)) catch {
            return error.OutOfMemory;
        };
        break :blk .{ fresh, 1 };
    };
    record.* = .{
        .base = .{ .target_fiber = target_fiber },
        .cached = .{
            .key = suspensionCacheKey(Spec),
            .deinitFn = SuspensionRecord(Spec).deinitCached,
        },
        .runtime = runtime,
        .target_frame = frame,
        .request = request,
        .generation = generation,
    };
    runtime.active_suspension_count += 1;
    current_fiber.state = .suspended;
    current_fiber.outcome = .{ .suspension = &record.base };
    tls_current_fiber = current_fiber.parent_fiber;
    shift_swap_context(&current_fiber.context, current_fiber.parent_context);
    switch (record.state) {
        .resumed => return record.resume_value.?,
        .discontinued => return record.discontinue_error.?,
        .pending => unreachable,
    }
}

test "no-capture reset returns complete step" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        const tag = struct {};
        const Request = void;
        const Resume = void;
        const Answer = usize;
        const ErrorSet = error{};
    };

    const step = try reset(demo_spec, &runtime, struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            return 7;
        }
    }.body);

    switch (step) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 7), answer),
        .suspended => unreachable,
    }
}

test "prompt token stays stable for the same tag type" {
    const tag = struct {};
    try std.testing.expectEqual(@intFromPtr(promptToken(tag)), @intFromPtr(promptToken(tag)));
}

test "prompt token differs for distinct tag types" {
    const tag_a = struct {};
    const tag_b = struct {};
    try std.testing.expect(@intFromPtr(promptToken(tag_a)) != @intFromPtr(promptToken(tag_b)));
}

test "prompt token differs across local namespaces" {
    const scope_a = struct {
        const tag = struct {};
    };
    const scope_b = struct {
        const tag = struct {};
    };
    try std.testing.expect(@intFromPtr(promptToken(scope_a.tag)) != @intFromPtr(promptToken(scope_b.tag)));
}

test "shift returns a suspended step and resume completes it" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        const tag = struct {};
        const Request = i32;
        const Resume = i32;
        const Answer = i32;
        const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const current = try shift(demo_spec, 41);
            return current + 1;
        }
    };

    var step = try reset(demo_spec, &runtime, demo.body);
    switch (step) {
        .complete => unreachable,
        .suspended => |*suspension| {
            try std.testing.expectEqual(@as(i32, 41), suspension.request);
            step = try suspension.resumeWith(41);
        },
    }
    switch (step) {
        .complete => |answer| try std.testing.expectEqual(@as(i32, 42), answer),
        .suspended => unreachable,
    }
}

test "discontinue injects the supplied error" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        const tag = struct {};
        const Request = void;
        const Resume = void;
        const Answer = usize;
        const ErrorSet = error{Stop};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            _ = try shift(demo_spec, {});
            return 99;
        }
    };

    var step = try reset(demo_spec, &runtime, demo.body);
    switch (step) {
        .complete => unreachable,
        .suspended => |*suspension| try std.testing.expectError(error.Stop, suspension.discontinue(error.Stop)),
    }
}

test "discontinue can be caught and produce another suspension" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        const tag = struct {};
        const Request = []const u8;
        const Resume = void;
        const Answer = usize;
        const ErrorSet = error{Stop};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            _ = shift(demo_spec, "first") catch |err| switch (err) {
                error.Stop => {},
                else => return err,
            };
            _ = try shift(demo_spec, "after-stop");
            return 7;
        }
    };

    var step = try reset(demo_spec, &runtime, demo.body);
    switch (step) {
        .complete => unreachable,
        .suspended => |*suspension| {
            try std.testing.expectEqualStrings("first", suspension.request);
            step = try suspension.discontinue(error.Stop);
        },
    }
    switch (step) {
        .complete => unreachable,
        .suspended => |*suspension| {
            try std.testing.expectEqualStrings("after-stop", suspension.request);
            step = try suspension.resumeWith({});
        },
    }
    switch (step) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 7), answer),
        .suspended => unreachable,
    }
}

test "suspension can escape the immediate reset call and resume later" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        const tag = struct {};
        const Request = []const u8;
        const Resume = usize;
        const Answer = usize;
        const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const resumed = try shift(demo_spec, "later");
            return resumed + 1;
        }
    };

    var saved: ?Suspension(demo_spec) = null;
    var step = try reset(demo_spec, &runtime, demo.body);
    switch (step) {
        .complete => unreachable,
        .suspended => |suspension| {
            try std.testing.expectEqualStrings("later", suspension.request);
            saved = suspension;
        },
    }
    step = try saved.?.resumeWith(41);
    switch (step) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 42), answer),
        .suspended => unreachable,
    }
}

test "copied suspension alias is rejected" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        const tag = struct {};
        const Request = usize;
        const Resume = usize;
        const Answer = usize;
        const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const resumed = try shift(demo_spec, 41);
            return resumed + 1;
        }
    };

    var step = try reset(demo_spec, &runtime, demo.body);
    switch (step) {
        .complete => unreachable,
        .suspended => |suspension| {
            var owner = suspension;
            var alias = suspension;
            step = try owner.resumeWith(41);
            try std.testing.expectError(error.SuspensionAliased, alias.resumeWith(41));
        },
    }
    switch (step) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 42), answer),
        .suspended => unreachable,
    }
}

test "resolved suspension records are recycled instead of retained linearly" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        const tag = struct {};
        const Request = usize;
        const Resume = usize;
        const Answer = usize;
        const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const resumed = try shift(demo_spec, 41);
            return resumed + 1;
        }
    };

    var first_step = try reset(demo_spec, &runtime, demo.body);
    const first_record = switch (first_step) {
        .complete => unreachable,
        .suspended => |*suspension| blk: {
            const record = suspension.record.?;
            first_step = try suspension.resumeWith(41);
            break :blk record;
        },
    };
    switch (first_step) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 42), answer),
        .suspended => unreachable,
    }
    try std.testing.expect(runtime.cached_suspensions != null);

    var second_step = try reset(demo_spec, &runtime, demo.body);
    switch (second_step) {
        .complete => unreachable,
        .suspended => |*suspension| {
            try std.testing.expectEqual(first_record, suspension.record.?);
            second_step = try suspension.resumeWith(41);
        },
    }
    switch (second_step) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 42), answer),
        .suspended => unreachable,
    }
}

test "no-shift guard rejects capture" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        const tag = struct {};
        const Request = void;
        const Resume = void;
        const Answer = usize;
        const ErrorSet = error{};
    };

    const demo = struct {
        var runtime_ptr: *Runtime = undefined;

        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            var guard: NoShiftGuard = .{};
            try guard.enter(runtime_ptr);
            defer guard.leave();
            _ = try shift(demo_spec, {});
            return 1;
        }
    };

    demo.runtime_ptr = &runtime;
    try std.testing.expectError(error.ShiftForbidden, reset(demo_spec, &runtime, demo.body));
}

test "no-shift guard checked leave rejects cross-thread use" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    var guard: NoShiftGuard = .{};
    try guard.enter(&runtime);
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

test "no-shift guard copied alias cannot release owner depth" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    var guard: NoShiftGuard = .{};
    try guard.enter(&runtime);
    var alias = guard;

    try std.testing.expectError(error.AlreadyResolved, alias.leaveChecked());
    try std.testing.expectEqual(@as(usize, 1), runtime.no_shift_depth);
    try guard.leaveChecked();
    try std.testing.expectEqual(@as(usize, 0), runtime.no_shift_depth);
}

test "runtime checked deinit rejects active reset" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        const tag = struct {};
        const Request = void;
        const Resume = void;
        const Answer = usize;
        const ErrorSet = error{ TestExpectedError, TestUnexpectedError };
    };

    const demo = struct {
        var runtime_ptr: *Runtime = undefined;

        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const inner = try reset(demo_spec, runtime_ptr, struct {
                fn nested() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
                    return 7;
                }
            }.nested);
            try std.testing.expectError(error.RuntimeBusy, runtime_ptr.deinitChecked());
            return switch (inner) {
                .complete => |answer| answer,
                .suspended => unreachable,
            };
        }
    };

    demo.runtime_ptr = &runtime;
    const step = try reset(demo_spec, &runtime, demo.body);
    switch (step) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 7), answer),
        .suspended => unreachable,
    }
}

test "runtime checked deinit rejects unresolved suspension and allows teardown after resolution" {
    var runtime = Runtime.init(std.testing.allocator, .{});

    const demo_spec = struct {
        const tag = struct {};
        const Request = usize;
        const Resume = usize;
        const Answer = usize;
        const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const resumed = try shift(demo_spec, 41);
            return resumed + 1;
        }
    };

    var step = try reset(demo_spec, &runtime, demo.body);
    try std.testing.expectError(error.RuntimeBusy, runtime.deinitChecked());
    switch (step) {
        .complete => unreachable,
        .suspended => |*suspension| step = try suspension.resumeWith(41),
    }
    switch (step) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 42), answer),
        .suspended => unreachable,
    }
    try runtime.deinitChecked();
}

test "runtime copied alias is rejected after first use" {
    var runtime = Runtime.init(std.testing.allocator, .{});

    const demo_spec = struct {
        const tag = struct {};
        const Request = void;
        const Resume = void;
        const Answer = usize;
        const ErrorSet = error{};
    };

    const step = try reset(demo_spec, &runtime, struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            return 7;
        }
    }.body);
    switch (step) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 7), answer),
        .suspended => unreachable,
    }

    var alias = runtime;
    try std.testing.expectError(error.RuntimeAliased, alias.deinitChecked());
    try runtime.deinitChecked();
}

test "runtime checked deinit rejects double teardown and later reset use" {
    var runtime = Runtime.init(std.testing.allocator, .{});

    try runtime.deinitChecked();
    try std.testing.expectError(error.RuntimeDestroyed, runtime.deinitChecked());

    const demo_spec = struct {
        const tag = struct {};
        const Request = void;
        const Resume = void;
        const Answer = usize;
        const ErrorSet = error{};
    };

    try std.testing.expectError(error.RuntimeDestroyed, reset(demo_spec, &runtime, struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            return 7;
        }
    }.body));
}

test "outer prompt suspension can bubble through an inner reset" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const outer_spec = struct {
        const tag = struct {};
        const Request = i32;
        const Resume = i32;
        const Answer = i32;
        const ErrorSet = error{};
    };

    const inner_spec = struct {
        const tag = struct {};
        const Request = i32;
        const Resume = i32;
        const Answer = i32;
        const ErrorSet = error{};
    };

    const demo = struct {
        var runtime_ptr: *Runtime = undefined;

        fn innerBody() ResetError(inner_spec.ErrorSet)!inner_spec.Answer {
            const current = try shift(outer_spec, 41);
            return current + 1;
        }

        fn outerBody() ResetError(outer_spec.ErrorSet)!outer_spec.Answer {
            var inner_step = try reset(inner_spec, runtime_ptr, innerBody);
            while (true) switch (inner_step) {
                .complete => |answer| return answer,
                .suspended => |*suspension| {
                    const resumed = try shift(outer_spec, suspension.request);
                    inner_step = try suspension.resumeWith(resumed);
                },
            };
        }
    };

    demo.runtime_ptr = &runtime;
    var step = try reset(outer_spec, &runtime, demo.outerBody);
    switch (step) {
        .complete => unreachable,
        .suspended => |*suspension| {
            try std.testing.expectEqual(@as(i32, 41), suspension.request);
            step = try suspension.resumeWith(41);
        },
    }
    switch (step) {
        .complete => |answer| try std.testing.expectEqual(@as(i32, 42), answer),
        .suspended => unreachable,
    }
}
