const shift = @import("shift");
const std = @import("std");

const Counter = shift.effect.Define(.{
    .state_type = i32,
    .ops = .{
        shift.effect.ops.Transform("get", void, i32),
        shift.effect.ops.Transform("set", i32, void),
    },
});

const CounterHandler = struct {
    state: i32,

    /// Read the current counter state.
    pub fn get(self: *@This()) i32 {
        return self.state;
    }

    /// Preserve the enclosing answer after a counter read.
    pub fn afterGet(_: *@This(), answer: i32) i32 {
        return answer;
    }

    /// Replace the current counter state.
    pub fn set(self: *@This(), value: i32) void {
        self.state = value;
    }

    /// Preserve the enclosing answer after a counter write.
    pub fn afterSet(_: *@This(), answer: i32) i32 {
        return answer;
    }
};

fn counterBody(eff: anytype) anyerror!i32 {
    const before = try eff.counter.get.perform();
    try eff.counter.set.perform(before + 1);
    const after = try eff.counter.get.perform();
    return after;
}

fn runCounter(runtime: *shift.Runtime) anyerror!i32 {
    const result = try shift.withAt(@src(), runtime, .{
        .counter = Counter.use(.{ .handler = CounterHandler{ .state = 5 } }),
    }, shift.NamedBody("examples/open_row_transform_basic.zig", "counterBody", anyerror!i32, counterBody));
    return result.value;
}

/// Render the transform example transcript.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    try writer.print("counter={d}\n", .{try runCounter(&runtime)});
}

/// Run the transform example on stdout.
pub fn main() anyerror!void {
    var stdout_buffer: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
