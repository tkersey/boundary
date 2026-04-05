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
    items: std.ArrayList([]u8) = .empty,

    /// Append one writer payload.
    pub fn tell(self: *@This(), value: []const u8) anyerror!void {
        try self.items.append(self.allocator, try self.allocator.dupe(u8, value));
    }

    /// Finish writer collection for one lowered run.
    pub fn finish(self: *@This()) anyerror![][]const u8 {
        const outputs = try self.allocator.alloc([]const u8, self.items.items.len);
        for (self.items.items, outputs) |item, *output| output.* = item;
        return outputs;
    }

    /// Release any retained writer items.
    pub fn deinit(self: *@This()) void {
        for (self.items.items) |item| self.allocator.free(item);
        self.items.deinit(self.allocator);
    }
};

/// One combined state-plus-writer handler bundle for lowered open-row examples.
pub const StateWriterHandlers = struct {
    state: StateHandler,
    writer: WriterHandler,
};

test "writer handler snapshots transient payload bytes" {
    var handler: WriterHandler = .{ .allocator = std.testing.allocator };
    defer handler.deinit();

    var transient = [_]u8{ 'o', 'k' };
    try handler.tell(transient[0..]);
    transient[0] = 'n';

    const outputs = try handler.finish();
    defer std.testing.allocator.free(outputs);

    try std.testing.expectEqual(@as(usize, 1), outputs.len);
    try std.testing.expectEqualStrings("ok", outputs[0]);
}
