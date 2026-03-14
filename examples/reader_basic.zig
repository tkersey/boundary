const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ReaderInstance = shift.effect.reader.Instance(i32, NoError);

const demo = struct {
    var env_value: i32 = 0;

    /// Execute the reader body for this example.
    pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
        env_value = try shift.effect.reader.ask(Cap, ctx);
        return env_value * 2;
    }
};

/// Write the reader-effect transcript for this example.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var instance = ReaderInstance.init();

    demo.env_value = 0;
    const answer = try shift.effect.reader.handle(i32, &runtime, &instance, 21, demo);

    try writer.print("env={d}\n", .{demo.env_value});
    try writer.print("value={d}\n", .{answer});
}

/// Run the additive reader-effect example using only the public effect surface.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
