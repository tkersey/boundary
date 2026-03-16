const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const Counter = shift.effect.Define(.{
    .mode = shift.PromptMode.resume_then_transform,
    .state_type = i32,
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Transform("get", void, i32),
        shift.effect.ops.Transform("set", i32, void),
    },
});

fn runCounter(runtime: *shift.Runtime) !i32 {
    const body = struct {
        /// Increment the generated counter once and return the new value.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            const before = try Counter.Op(.get).perform(Cap, ctx);
            try Counter.Op(.set).perform(Cap, ctx, before + 1);
            return try Counter.Op(.get).perform(Cap, ctx);
        }
    };
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

    var instance = Counter.Instance.init();
    const result = try Counter.proof.exampleHarness(i32, runtime, &instance, Handler{ .state = 5 }, body);
    return result.value;
}

/// Render the generated-family example transcript.
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
