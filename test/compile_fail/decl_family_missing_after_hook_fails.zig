const shift = @import("shift");
const std = @import("std");

const BadHandler = struct {
    state: i32,

    pub fn get(self: *@This()) i32 {
        return self.state;
    }
};

const Counter = shift.Decl.family(.{
    .state_type = i32,
    .ops = .{
        shift.Op.transform("get", void, i32),
    },
}, BadHandler);

const Demo = shift.Program(.{
    .counter = Counter,
}, struct {
    pub fn body(eff: anytype) !i32 {
        return try eff.counter.get.perform();
    }
});

pub fn main() !void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try shift.run(&runtime, Demo, .{
        .counter = BadHandler{ .state = 0 },
    });
}
