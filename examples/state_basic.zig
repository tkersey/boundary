const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const StateInstance = shift.effect.state.Instance(i32, NoError);
const StateContext = shift.effect.state.Context(i32, i32, NoError);

const demo = struct {
    var before_value: i32 = 0;
    var after_value: i32 = 0;

    fn increment(ctx: anytype) shift.ResetError(NoError)!i32 {
        before_value = try ctx.get();
        try ctx.set(before_value + 1);
        after_value = try ctx.get();
        return before_value + after_value;
    }

    fn body(ctx: *StateContext) shift.ResetError(NoError)!i32 {
        return try increment(ctx);
    }
};

/// Write the state-effect transcript for this example.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var instance = StateInstance.init();

    demo.before_value = 0;
    demo.after_value = 0;
    const result = try shift.effect.state.handle(i32, &runtime, &instance, 5, demo.body);

    try writer.print("before={d}\n", .{demo.before_value});
    try writer.print("after={d}\n", .{demo.after_value});
    try writer.print("final_state={d}\n", .{result.state});
    try writer.print("value={d}\n", .{result.value});
}

/// Run the additive state-effect example using only the public effect surface.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
