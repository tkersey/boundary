const ability = @import("ability");
const std = @import("std");

const Counter = ability.effect.Define(.{
    .state_type = i32,
    .ops = .{
        ability.effect.ops.Transform("get", void, i32),
        ability.effect.ops.Transform("set", i32, void),
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

fn runCounter(runtime: *ability.Runtime) anyerror!i32 {
    const result = try ability.with(runtime, .{
        .counter = Counter.use(.{ .handler = CounterHandler{ .state = 5 } }),
    }, struct {
        /// Run the transform example body through the lexical front door.
        pub fn body(eff: anytype) @TypeOf(counterBody(eff)) {
            return counterBody(eff);
        }
    });
    return result.value;
}

/// Render the transform example transcript.
pub fn run(writer: anytype) anyerror!void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    try writer.print("counter={d}\n", .{try runCounter(&runtime)});
}

/// Run the transform example on stdout.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [128]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
