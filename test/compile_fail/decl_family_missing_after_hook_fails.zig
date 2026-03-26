const shift = @import("shift");
const std = @import("std");

const BadHandler = struct {
    state: i32,

    /// Public `get` helper.
    pub fn get(self: *@This()) i32 {
        return self.state;
    }
};

const Counter = shift.Decl.family(.{
    .state_type = i32,
    .ops = .{
        shift.Op.Transform("get", void, i32),
    },
}, BadHandler);

const Demo = shift.Program(.{
    .counter = Counter,
}, struct {
    /// Execute this public body hook.
    pub fn body(eff: anytype) !i32 {
        return try eff.counter.get.perform();
    }
});

/// Run this public entrypoint.
pub fn main() !void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try shift.run(&runtime, Demo, .{
        .counter = BadHandler{ .state = 0 },
    });
}
