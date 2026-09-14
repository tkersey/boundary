const std = @import("std");
const d = @import("boundary_data_v2");
pub fn main(init: std.process.Init) !void {
    var nodes: [128]d.graph.Node = undefined;
    const value: d.graph.Value = .{ .schema = 0, .body = .{ .blob = .{ .id = 0 } } };
    for (&nodes, 0..) |*node, index| node.* = .{ .environment = .{
        .values = &.{value},
        .tail = .{ .id = (index + 1) % nodes.len },
    } };
    const state: d.graph.State = .{ .program_identity = .{0} ** 32, .status = .active, .roots = .{ .current = .{ .id = 0 } }, .nodes = &nodes, .blobs = &.{.{ .schema = 0, .bytes = "retained immutable payload" }} };
    var tracked = std.testing.FailingAllocator.init(init.gpa, .{});
    var result = try d.snapshot.canonicalize(tracked.allocator(), state);
    const retained = tracked.allocated_bytes - tracked.freed_bytes;
    const length = try d.snapshot.encodedLength(init.gpa, result.state);
    const bytes = try init.gpa.alloc(u8, length);
    defer init.gpa.free(bytes);
    _ = try d.snapshot.encode(init.gpa, result.state, bytes);
    result.deinit();
    std.debug.assert(tracked.allocated_bytes == tracked.freed_bytes);
    std.debug.print("retained={d} bytes={d} digest={x}\n", .{ retained, length, d.wire.digest(bytes) });
}
