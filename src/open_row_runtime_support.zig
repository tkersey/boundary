const std = @import("std");

/// One state handler used by lowered open-row example runners.
pub const StateHandler = struct {
    value: i32,

    /// Return the current state value.
    pub fn get(self: *@This()) anyerror!i32 {
        return self.value;
    }

    /// Update the current state value.
    pub fn set(self: *@This(), value: i32) anyerror!void {
        self.value = value;
    }

    /// Finish state collection for one lowered run.
    pub fn finish(self: *@This()) i32 {
        return self.value;
    }
};

/// One writer handler used by lowered open-row example runners.
pub const WriterHandler = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList([]const u8) = .empty,

    /// Append one writer payload.
    pub fn tell(self: *@This(), value: []const u8) anyerror!void {
        try self.items.append(self.allocator, value);
    }

    /// Finish writer collection for one lowered run.
    pub fn finish(self: *@This()) anyerror![][]const u8 {
        return try self.items.toOwnedSlice(self.allocator);
    }

    /// Release any retained writer items.
    pub fn deinit(self: *@This()) void {
        self.items.deinit(self.allocator);
    }
};

/// One combined state-plus-writer handler bundle for lowered open-row examples.
pub const StateWriterHandlers = struct {
    state: StateHandler,
    writer: WriterHandler,
};
