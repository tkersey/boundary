const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const WriterInstance = shift.effect.writer.Instance([]const u8, NoError);

const demo = struct {
    /// Append two items to the writer log and then return normally.
    pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)![]const u8 {
        try shift.effect.writer.tell(Cap, ctx, "a");
        try shift.effect.writer.tell(Cap, ctx, "b");
        return "done";
    }
};

/// Write the writer-effect transcript for this example.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var instance = WriterInstance.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const result = try shift.effect.writer.handle([]const u8, []const u8, &runtime, &instance, arena.allocator(), demo);

    for (result.items) |item| try writer.print("item={s}\n", .{item});
    try writer.print("value={s}\n", .{result.value});
}

/// Run the writer effect example using only the public effect surface.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
