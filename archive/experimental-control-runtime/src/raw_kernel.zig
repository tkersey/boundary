const builtin = @import("builtin");
const std = @import("std");

/// Runtime errors surfaced by the fiber-backed control core.
pub const Error = error{
    AlreadyResolved,
    Cancelled,
    CancellationRecovered,
    CrossThread,
    MissingPrompt,
    OutOfMemory,
    OwnerAliased,
    PromptAliased,
    RuntimeAliased,
    RuntimeBusy,
    RuntimeDestroyed,
    ShiftForbidden,
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

/// Resolve the request payload type for a specialization spec.
pub fn RequestOf(comptime PromptType: type) type {
    return @field(PromptType, "Request");
}

/// Resolve the resume payload type for a specialization spec.
pub fn ResumeOf(comptime PromptType: type) type {
    return @field(PromptType, "Resume");
}

/// Resolve the answer type for a specialization spec.
pub fn AnswerOf(comptime PromptType: type) type {
    return @field(PromptType, "Answer");
}

/// Resolve the user-owned error set type for a specialization spec.
pub fn ErrorSetOf(comptime PromptType: type) type {
    return @field(PromptType, "ErrorSet");
}

/// Report whether a specialization carries a payloadless resume edge.
pub fn resumeIsVoid(comptime PromptType: type) bool {
    return ResumeOf(PromptType) == void;
}

/// Report whether a specialization exposes user-owned discontinue.
pub fn supportsDiscontinue(comptime ErrorSet: type) bool {
    return switch (@typeInfo(ErrorSet)) {
        .error_set => |errors| errors == null or errors.?.len != 0,
        else => true,
    };
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

    /// Confirm the runtime is being used from its owning thread and stable owner.
    pub fn ensureThread(self: *Runtime) Error!void {
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

    /// Remove one cached suspension record matching the given specialization key.
    pub fn popCachedSuspension(self: *Runtime, comptime Record: type, key: usize) ?*Record {
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

    /// Return a suspension record to the runtime-local cache.
    pub fn pushCachedSuspension(self: *Runtime, node: *CachedSuspension) void {
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

/// Return the stable prompt identity marker for a prompt handle instance.
pub fn promptToken(prompt: anytype) Error!PromptToken {
    const PromptType = @TypeOf(prompt.*);
    if (!@hasField(PromptType, "marker")) {
        @compileError(@typeName(PromptType) ++ " must expose a marker field");
    }
    if (!@hasField(PromptType, "owner_cookie")) {
        @compileError(@typeName(PromptType) ++ " must expose an owner_cookie field");
    }
    if (prompt.owner_cookie == 0) {
        prompt.owner_cookie = @intFromPtr(prompt);
    } else if (prompt.owner_cookie != @intFromPtr(prompt)) {
        return error.PromptAliased;
    }
    return @ptrCast(&prompt.marker);
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

pub extern fn shift_swap_context(from: *Context, to: *const Context) callconv(.c) void;

/// Current runtime active on this thread while executing inside `shift`.
pub threadlocal var tls_runtime: ?*Runtime = null;
/// Current fiber active on this thread while executing inside `shift`.
pub threadlocal var tls_current_fiber: ?*FiberBase = null;

/// Internal machine state for the currently executing delimited computation.
const MachineState = enum {
    done,
    failed,
    ready,
    running,
    suspended,
};

/// Signal emitted by the machine when control returns to a parent frame.
const MachineSignal = union(enum) {
    none,
    suspension: *SuspensionBase,
};

/// Runtime-owned fiber record used by the stackful kernel.
const FiberBase = struct {
    runtime: *Runtime,
    parent_fiber: ?*FiberBase,
    parent_context: *Context,
    context: Context = .{},
    stack: Stack,
    prompt_token: PromptToken,
    machine_state: MachineState = .ready,
    machine_signal: MachineSignal = .none,
    startFn: *const fn (*FiberBase) noreturn,
};

/// Minimal suspension edge shared between the kernel and surface layers.
const SuspensionBase = struct {
    target_fiber: *FiberBase,
};

/// Construct the delimiter frame type for a particular prompt specialization.
pub fn ResetFrame(comptime PromptType: type) type {
    return struct {
        cached: CachedFrame,
        base: FiberBase,
        body: *const fn () ResetError(ErrorSetOf(PromptType))!AnswerOf(PromptType),
        cancellation_required: bool = false,
        result: union(enum) {
            answer: AnswerOf(PromptType),
            err: ResetError(ErrorSetOf(PromptType)),
            none,
        } = .none,

        /// Allocate or reuse a reset frame for this specialization.
        pub fn create(runtime: *Runtime, prompt: anytype, body: *const fn () ResetError(ErrorSetOf(PromptType))!AnswerOf(PromptType)) ResetError(ErrorSetOf(PromptType))!*@This() {
            const frame = runtime.popCachedFrame(@This(), frameCacheKey(PromptType)) orelse try runtime.allocator.create(@This());
            const parent_fiber = tls_current_fiber;
            const parent_context = if (parent_fiber) |fiber| &fiber.context else &runtime.root_context;
            const stack = try runtime.acquireStack();
            frame.* = .{
                .cached = .{
                    .key = frameCacheKey(PromptType),
                    .deinitFn = freeCached,
                },
                .base = .{
                    .runtime = runtime,
                    .parent_fiber = parent_fiber,
                    .parent_context = parent_context,
                    .stack = stack,
                    .prompt_token = try promptToken(prompt),
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

        /// Return the frame's stack and frame storage to the runtime caches.
        pub fn destroy(self: *@This()) void {
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
            base.machine_state = .running;
            const answer = self.body() catch |err| finishCurrentFiberWithError(PromptType, self, err);
            finishCurrentFiberWithAnswer(PromptType, self, answer);
        }
    };
}

fn FrameCacheMarker(comptime PromptType: type) type {
    return struct {
        const _prompt_type = PromptType;
        var marker: u8 = 0;
    };
}

fn frameCacheKey(comptime PromptType: type) usize {
    return @intFromPtr(&FrameCacheMarker(PromptType).marker);
}

fn SuspensionCacheMarker(comptime PromptType: type) type {
    return struct {
        const _prompt_type = PromptType;
        var marker: u8 = 0;
    };
}

/// Return the cache key used for suspension-record reuse for a spec.
pub fn suspensionCacheKey(comptime PromptType: type) usize {
    return @intFromPtr(&SuspensionCacheMarker(PromptType).marker);
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

fn finishCurrentFiberWithAnswer(comptime PromptType: type, frame: *ResetFrame(PromptType), answer: AnswerOf(PromptType)) noreturn {
    if (frame.cancellation_required) {
        finishCurrentFiberWithError(PromptType, frame, error.CancellationRecovered);
    }
    frame.result = .{ .answer = answer };
    frame.base.machine_state = .done;
    frame.base.machine_signal = .none;
    tls_current_fiber = frame.base.parent_fiber;
    shift_swap_context(&frame.base.context, frame.base.parent_context);
    unreachable;
}

fn finishCurrentFiberWithError(comptime PromptType: type, frame: *ResetFrame(PromptType), err: ResetError(ErrorSetOf(PromptType))) noreturn {
    const final_err = if (frame.cancellation_required and err != error.Cancelled) @as(ResetError(ErrorSetOf(PromptType)), error.CancellationRecovered) else err;
    frame.result = .{ .err = final_err };
    frame.base.machine_state = .failed;
    frame.base.machine_signal = .none;
    tls_current_fiber = frame.base.parent_fiber;
    shift_swap_context(&frame.base.context, frame.base.parent_context);
    unreachable;
}

/// Construct the suspension record that represents one unresolved pending edge.
pub fn SuspensionRecord(comptime PromptType: type) type {
    return struct {
        base: SuspensionBase,
        cached: CachedSuspension,
        runtime: *Runtime,
        target_frame: *ResetFrame(PromptType),
        request: RequestOf(PromptType),
        generation: usize = 1,
        owner_cookie: usize = 0,
        resolution: enum {
            cancelled,
            discontinued,
            pending,
            resumed,
        } = .pending,
        resume_value: ?ResumeOf(PromptType) = null,
        discontinue_error: ?ErrorSetOf(PromptType) = null,

        /// Release a cached suspension record allocated for this specialization.
        pub fn deinitCached(node: *CachedSuspension, allocator: std.mem.Allocator) void {
            const self: *@This() = @fieldParentPtr("cached", node);
            allocator.destroy(self);
        }
    };
}

/// Test-only probe for whether the runtime currently has cached suspensions.
pub fn testingHasCachedSuspensions(runtime: *Runtime) bool {
    return runtime.cached_suspensions != null;
}

comptime {
    _ = resumeIsVoid;
    _ = supportsDiscontinue;
    _ = suspensionCacheKey;
    _ = SuspensionRecord;
}

test "prompt token stays stable for the same tag type" {
    var prompt = struct {
        marker: u8 = 0,
        owner_cookie: usize = 0,
    }{};
    try std.testing.expectEqual(@intFromPtr(try promptToken(&prompt)), @intFromPtr(try promptToken(&prompt)));
}

test "prompt token differs for distinct tag types" {
    var prompt_a = struct {
        marker: u8 = 0,
        owner_cookie: usize = 0,
    }{};
    var prompt_b = struct {
        marker: u8 = 0,
        owner_cookie: usize = 0,
    }{};
    try std.testing.expect(@intFromPtr(try promptToken(&prompt_a)) != @intFromPtr(try promptToken(&prompt_b)));
}

test "prompt token differs across local namespaces" {
    var prompt_a = struct {
        marker: u8 = 0,
        owner_cookie: usize = 0,
    }{};
    var prompt_b = struct {
        marker: u8 = 0,
        owner_cookie: usize = 0,
    }{};
    try std.testing.expect(@intFromPtr(try promptToken(&prompt_a)) != @intFromPtr(try promptToken(&prompt_b)));
}
