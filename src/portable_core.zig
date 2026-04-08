const std = @import("std");

/// Stable prompt token shape shared across compat and canonical paths.
pub const PromptToken = usize;

const prompt_token_bits = @bitSizeOf(PromptToken);
const explicit_prompt_marker = @as(PromptToken, 1) << (prompt_token_bits - 1);
const explicit_payload_bits = prompt_token_bits - 1;
const explicit_source_bits = explicit_payload_bits / 2;
const explicit_local_bits = explicit_payload_bits - explicit_source_bits;
const pending_source_tag = std.math.maxInt(PromptToken);

fn bitMask(comptime bit_count: comptime_int) PromptToken {
    if (bit_count == 0) return 0;
    return std.math.maxInt(PromptToken) >> @as(std.math.Log2Int(PromptToken), @intCast(prompt_token_bits - bit_count));
}

const max_explicit_source_tag = bitMask(explicit_source_bits);
const max_explicit_local_token = bitMask(explicit_local_bits);
const max_compat_prompt_token = explicit_prompt_marker - 1;

fn encodeExplicitPromptToken(source_tag: PromptToken, local_token: PromptToken) PromptToken {
    return explicit_prompt_marker | (source_tag << explicit_local_bits) | local_token;
}

const SpinLock = struct {
    state: u8 = 0,

    fn lock(self: *@This()) void {
        while (@cmpxchgWeak(u8, &self.state, 0, 1, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    fn unlock(self: *@This()) void {
        @atomicStore(u8, &self.state, 0, .release);
    }
};

/// Core lifecycle state for one execution owner.
pub const LifecycleState = enum {
    alive,
    destroyed,
};

/// Explicit prompt-token allocator used by canonical and compat shells.
pub const PromptTokenSource = struct {
    next_token: PromptToken = 1,
    source_tag: PromptToken = pending_source_tag,
    lock_state: SpinLock = .{},

    /// Allocate one distinct prompt token, failing closed on overflow.
    pub fn allocate(self: *@This()) PromptToken {
        self.lock_state.lock();
        defer self.lock_state.unlock();
        const local_token = self.next_token;
        const source_tag = self.ensureSourceTag();
        if (source_tag == 0) {
            if (local_token > max_compat_prompt_token) {
                std.debug.panic("compat prompt token overflow", .{});
            }
            self.next_token += 1;
            return local_token;
        }
        if (local_token > max_explicit_local_token) {
            std.debug.panic("prompt token overflow", .{});
        }
        self.next_token += 1;
        return encodeExplicitPromptToken(source_tag, local_token);
    }

    fn ensureSourceTag(self: *@This()) PromptToken {
        if (self.source_tag != pending_source_tag) return self.source_tag;
        self.source_tag = explicit_source_tags.allocate();
        return self.source_tag;
    }
};

const ExplicitSourceTagAllocator = struct {
    next_tag: PromptToken = 1,
    lock_state: SpinLock = .{},

    fn allocate(self: *@This()) PromptToken {
        self.lock_state.lock();
        defer self.lock_state.unlock();
        const source_tag = self.next_tag;
        if (source_tag == 0 or source_tag > max_explicit_source_tag) {
            std.debug.panic("prompt source overflow", .{});
        }
        self.next_tag += 1;
        return source_tag;
    }
};

/// Type-erased prompt-frame registry entry map.
pub const FrameRegistry = struct {
    map: std.AutoHashMapUnmanaged(PromptToken, *anyopaque) = .empty,

    /// Resolve one typed active frame pointer by prompt token.
    pub fn find(self: *const @This(), comptime FramePtrType: type, token: PromptToken) ?FramePtrType {
        const raw = self.map.get(token) orelse return null;
        return @ptrCast(@alignCast(raw));
    }

    /// Install one active frame and return the previous entry for the same token, if any.
    pub fn push(self: *@This(), allocator: std.mem.Allocator, token: PromptToken, frame: anytype) std.mem.Allocator.Error!?*anyopaque {
        const previous = self.map.get(token);
        try self.map.put(allocator, token, @ptrCast(frame));
        return previous;
    }

    /// Restore the previous active frame for this token or clear the entry.
    pub fn pop(self: *@This(), token: PromptToken, previous: ?*anyopaque) void {
        if (previous) |prior| {
            if (self.map.getPtr(token)) |entry| {
                entry.* = prior;
            }
            return;
        }
        _ = self.map.remove(token);
    }

    /// Release storage retained by this registry.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.map.deinit(allocator);
        self.* = .{};
    }
};

/// Type-erased cleanup frame used by explicit cleanup stacks.
pub const CleanupFrame = struct {
    previous: ?*CleanupFrame = null,
    cleanupFn: *const fn (*CleanupFrame) anyerror!void,
};

/// Explicit cleanup-frame stack owned by an execution core.
pub const CleanupStack = struct {
    active_frame: ?*CleanupFrame = null,

    /// Return the current cleanup stack marker.
    pub fn checkpoint(self: *const @This()) ?*CleanupFrame {
        return self.active_frame;
    }

    /// Push one cleanup frame onto this stack.
    pub fn push(self: *@This(), frame: *CleanupFrame) void {
        frame.previous = self.active_frame;
        self.active_frame = frame;
    }

    /// Unwind cleanup frames until `marker` becomes current again.
    pub fn unwindTo(self: *@This(), marker: ?*CleanupFrame) anyerror!void {
        var first_err: ?anyerror = null;
        while (self.active_frame != marker) {
            const frame = self.active_frame orelse {
                std.debug.panic("cleanup stack underflow", .{});
            };
            self.active_frame = frame.previous;
            frame.cleanupFn(frame) catch |err| {
                if (first_err == null) first_err = err;
            };
        }
        if (first_err) |err| return err;
    }
};

const SharedFrameRegistry = struct {
    lock_state: SpinLock = .{},
    registry: FrameRegistry = .{},

    fn find(self: *const @This(), comptime FramePtrType: type, token: PromptToken) ?FramePtrType {
        const mutable_self: *@This() = @constCast(self);
        mutable_self.lock_state.lock();
        defer mutable_self.lock_state.unlock();
        return self.registry.find(FramePtrType, token);
    }

    fn push(self: *@This(), allocator: std.mem.Allocator, token: PromptToken, frame: anytype) std.mem.Allocator.Error!?*anyopaque {
        _ = allocator;
        self.lock_state.lock();
        defer self.lock_state.unlock();
        return try self.registry.push(std.heap.page_allocator, token, frame);
    }

    fn pop(self: *@This(), token: PromptToken, previous: ?*anyopaque) void {
        self.lock_state.lock();
        defer self.lock_state.unlock();
        self.registry.pop(token, previous);
    }

    fn count(self: *const @This()) usize {
        const mutable_self: *@This() = @constCast(self);
        mutable_self.lock_state.lock();
        defer mutable_self.lock_state.unlock();
        return self.registry.map.count();
    }

    fn deinitIfIdle(self: *@This()) void {
        self.lock_state.lock();
        defer self.lock_state.unlock();
        if (self.registry.map.count() != 0) return;
        self.registry.deinit(std.heap.page_allocator);
    }
};

/// Canonical execution owner for lifecycle, prompt tokens, frames, and cleanup state.
pub const ExecutionCore = struct {
    allocator: std.mem.Allocator,
    state: LifecycleState = .alive,
    active_reset_count: usize = 0,
    prompt_tokens: *PromptTokenSource,
    frames: FrameRegistry = .{},
    cleanup: CleanupStack = .{},

    /// Build one core using the current compatibility token and frame registries.
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .prompt_tokens = compatPromptTokens(),
        };
    }

    /// Release owned frame-registry storage.
    pub fn deinit(self: *@This()) void {
        self.frames.deinit(self.allocator);
    }
};

var compat_prompt_tokens = PromptTokenSource{ .source_tag = 0 };
var compat_frames = SharedFrameRegistry{};
var explicit_source_tags = ExplicitSourceTagAllocator{};

/// Return the compatibility prompt-token source used by legacy `Prompt.init()`.
pub fn compatPromptTokens() *PromptTokenSource {
    return &compat_prompt_tokens;
}

/// Resolve one active compat frame pointer by prompt token.
pub fn compatFrameFind(comptime FramePtrType: type, token: PromptToken) ?FramePtrType {
    return compat_frames.find(FramePtrType, token);
}

/// Install one compat frame using the shared global page-backed registry.
pub fn compatFramePush(allocator: std.mem.Allocator, token: PromptToken, frame: anytype) std.mem.Allocator.Error!?*anyopaque {
    return try compat_frames.push(allocator, token, frame);
}

/// Restore the previous compat frame for this token or clear the entry.
pub fn compatFramePop(token: PromptToken, previous: ?*anyopaque) void {
    compat_frames.pop(token, previous);
}

/// Return the current compat frame count.
pub fn compatFrameCount() usize {
    return compat_frames.count();
}

/// Release compat-frame storage once the global registry is idle.
pub fn compatFrameDeinitIfIdle() void {
    compat_frames.deinitIfIdle();
}

test "compat frame registry ignores runtime allocators and deinitializes through page allocator" {
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

    compatFrameDeinitIfIdle();

    var owner = CountingAllocator.init(std.testing.allocator);
    var other = CountingAllocator.init(std.testing.allocator);
    var frame_a: usize = 1;
    var frame_b: usize = 2;

    _ = try compatFramePush(owner.allocator(), 11, &frame_a);
    _ = try compatFramePush(other.allocator(), 12, &frame_b);
    try std.testing.expect(compatFrameCount() == 2);

    compatFramePop(11, null);
    compatFramePop(12, null);
    try std.testing.expect(compatFrameCount() == 0);

    compatFrameDeinitIfIdle();
    try std.testing.expectEqual(@as(usize, 0), owner.alloc_calls);
    try std.testing.expectEqual(@as(usize, 0), owner.free_calls);
    try std.testing.expectEqual(@as(usize, 0), other.alloc_calls);
    try std.testing.expectEqual(@as(usize, 0), other.free_calls);
}
