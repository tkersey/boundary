const shift = @import("shift");
const std = @import("std");

fn runWithAllocator(writer: anytype, allocator: std.mem.Allocator) anyerror!void {
    var runtime = shift.Runtime.init(allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .writer = shift.effect.writer.use([]const u8, allocator),
    }, struct {
        /// Append two items and return the canonical writer answer.
        pub fn body(eff: anytype) ![]const u8 {
            try eff.writer.tell("a");
            try eff.writer.tell("b");
            return "done";
        }
    });
    defer allocator.free(result.outputs.writer);

    for (result.outputs.writer) |item| {
        try writer.print("item={s}\n", .{item});
    }
    try writer.print("value={s}\n", .{result.value});
}

/// Write the writer-effect transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    try runWithAllocator(writer, std.heap.page_allocator);
}

/// Run the writer-effect example.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
