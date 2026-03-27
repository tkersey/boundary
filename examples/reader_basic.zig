const shift = @import("shift");
const std = @import("std");

const ReaderRow = shift.effects.reader(i32);

const ReaderWorkflow = struct {
    pub const Uses = shift.Uses(ReaderRow);

    /// Read the front-door reader environment once and double it.
    pub fn body(eff: anytype) anyerror!i32 {
        const env = try eff.reader.ask();
        return env * 2;
    }
};

/// Write the reader-effect transcript through the root front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const closed = shift.bind(ReaderWorkflow, .{
        .reader = shift.handlers.reader(@as(i32, 21)),
    });
    const result = try shift.run(&runtime, closed);

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
