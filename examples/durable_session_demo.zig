const shift = @import("shift");
const std = @import("std");

/// Run the append-only durable session demo.
pub fn main() anyerror!void {
    try std.fs.cwd().makePath(".zig-cache/durable-session-demo");
    const store = shift.durable.Store.init(
        std.heap.page_allocator,
        ".zig-cache/durable-session-demo/session.manifest.json",
        ".zig-cache/durable-session-demo/events.jsonl",
    );

    _ = try store.saveScenario(.direct_return);
    const restored = try store.restore();
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("restore={s}\n", .{@tagName(restored.status)});
    try stdout.flush();
}
