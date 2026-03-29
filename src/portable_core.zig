const std = @import("std");

/// Stable prompt token shape shared across compat and canonical paths.
pub const PromptToken = usize;

/// Core lifecycle state for one execution owner.
pub const LifecycleState = enum {
    alive,
    destroyed,
};

/// Explicit prompt-token allocator used by canonical and compat shells.
pub const PromptTokenSource = struct {
    next_token: PromptToken = 1,

    /// Allocate one distinct prompt token, failing closed on overflow.
    pub fn allocate(self: *@This()) PromptToken {
        const token = self.next_token;
        if (token == std.math.maxInt(PromptToken)) {
            std.debug.panic("prompt token overflow", .{});
        }
        self.next_token += 1;
        return token;
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

var compat_prompt_tokens = PromptTokenSource{};
var compat_frames = FrameRegistry{};
var compat_cleanup = CleanupStack{};

/// Return the compatibility prompt-token source used by legacy `Prompt.init()`.
pub fn compatPromptTokens() *PromptTokenSource {
    return &compat_prompt_tokens;
}

/// Return the compatibility frame registry used by prompt-only replay lookups.
pub fn compatFrameRegistry() *FrameRegistry {
    return &compat_frames;
}

/// Return the compatibility cleanup stack used by transitional zero-arg helpers.
pub fn compatCleanupStack() *CleanupStack {
    return &compat_cleanup;
}
