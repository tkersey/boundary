const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const Counter = shift.effect.Define(.{
    .state_type = i32,
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Transform("get", void, i32),
        shift.effect.ops.Transform("set", i32, void),
    },
});

fn runCounter() !i32 {
    const Handler = struct {
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

    const result = try shift.with(.{
        .counter = Counter.use(.{ .handler = Handler{ .state = 5 } }),
    }, struct {
        /// Increment the generated counter once and return the new value.
        pub fn body(eff: anytype) shift.ResetError(NoError)!i32 {
            const before = try eff.counter.get.perform();
            try eff.counter.set.perform(before + 1);
            return try eff.counter.get.perform();
        }
    });
    return result.value;
}

/// Render the generated-family example transcript.
pub fn run(writer: anytype) anyerror!void {
    try writer.print("counter={d}\n", .{try runCounter()});
}

/// Run the generated-family example on stdout.
pub fn main() anyerror!void {
    var stdout_buffer: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
