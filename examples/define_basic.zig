const shift = @import("shift");
const std = @import("std");

const CounterHandler = struct {
    state: i32,

    /// Read the current generated counter state.
    pub fn get(self: *@This()) i32 {
        return self.state;
    }

    /// Preserve the enclosing answer after a generated counter read.
    pub fn afterGet(_: *@This(), answer: i32) i32 {
        return answer;
    }

    /// Replace the current generated counter state.
    pub fn set(self: *@This(), value: i32) void {
        self.state = value;
    }

    /// Preserve the enclosing answer after a generated counter write.
    pub fn afterSet(_: *@This(), answer: i32) i32 {
        return answer;
    }
};

const Counter = shift.Decl.family(.{
    .state_type = i32,
    .ops = .{
        shift.Ops.Transform("get", void, i32),
        shift.Ops.Transform("set", i32, void),
    },
}, CounterHandler);

const CounterProgram = shift.Program(.{
    .counter = Counter,
}, struct {
    /// Increment the generated counter once and return the new value.
    pub fn body(eff: anytype) !i32 {
        const before = try eff.counter.get.perform();
        try eff.counter.set.perform(before + 1);
        return try eff.counter.get.perform();
    }
});

fn runCounter(runtime: *shift.Runtime) !i32 {
    const result = try shift.run(runtime, CounterProgram, .{
        .counter = CounterHandler{ .state = 5 },
    });
    return result.value;
}

/// Render the generated-family example transcript through the root front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    try writer.print("counter={d}\n", .{try runCounter(&runtime)});
}

/// Run the generated-family example on stdout.
pub fn main() anyerror!void {
    var stdout_buffer: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
