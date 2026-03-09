const shift = @import("shift");
const std = @import("std");

const tag = struct {};
const NoError = error{};

const demo = struct {
    var resumed: i32 = 0;

    fn handleValue(k: *shift.Continuation(i32, tag, i32, NoError)) shift.ResetError(NoError)!i32 {
        resumed = 41;
        return try k.resumeWith(resumed);
    }

    fn body() shift.ResetError(NoError)!i32 {
        const current = try shift.shift(i32, tag, i32, NoError, handleValue);
        return current + 1;
    }
};

/// Run the state example.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    const answer = try shift.reset(tag, i32, NoError, &runtime, demo.body);

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("answer={d} resumed={d}\n", .{ answer, demo.resumed });
    try stdout.flush();
}
