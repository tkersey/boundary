const shift = @import("shift");
const std = @import("std");

const WriterProgram = shift.Program(.{
    .writer = shift.Decl.writer([]const u8),
}, struct {
    /// Append two items and return the canonical writer answer.
    pub fn body(eff: anytype) ![]const u8 {
        try eff.writer.tell("a");
        try eff.writer.tell("b");
        return "done";
    }
});

/// Write the writer-effect transcript through the root front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const result = try shift.run(&runtime, WriterProgram, .{});

    for (result.outputs.writer) |item| {
        try writer.print("item={s}\n", .{item});
    }
    try writer.print("value={s}\n", .{result.value});
}

/// Run the writer-effect example.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
