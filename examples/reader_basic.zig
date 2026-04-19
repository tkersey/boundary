const shift = @import("shift");
const std = @import("std");

fn readerBody(eff: anytype) anyerror!i32 {
    const env = try eff.reader.ask();
    return env + env;
}

/// Write the reader-effect transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .reader = shift.effect.reader.use(@as(i32, 21)),
    }, shift.NamedBody("examples/reader_basic.zig", "readerBody", anyerror!i32, readerBody));

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
