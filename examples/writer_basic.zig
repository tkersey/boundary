const ability = @import("ability");
const std = @import("std");

fn writerBody(eff: anytype) anyerror![]const u8 {
    try eff.writer.tell("a");
    try eff.writer.tell("b");
    return "done";
}

fn runWithAllocator(writer: anytype, allocator: std.mem.Allocator) anyerror!void {
    var runtime = ability.Runtime.init(allocator);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .writer = ability.effect.writer.use([]const u8, allocator),
    }, struct {
        /// Run the writer example body through the plain lexical surface.
        pub fn body(eff: anytype) anyerror![]const u8 {
            return writerBody(eff);
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
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
