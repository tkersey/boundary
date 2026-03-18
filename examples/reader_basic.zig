const shift = @import("shift");
const std = @import("std");

const NoError = error{};

/// Write the reader-effect transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .reader = shift.effect.reader.use(@as(i32, 21)),
    }, struct {
        /// Read the lexical reader environment once and double it.
        pub fn body(eff: anytype) !i32 {
            const env = try eff.reader.ask();
            return env * 2;
        }
    });

    try writer.print("env=21\nvalue={d}\n", .{result.value});
}

/// Run the reader-effect example.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
