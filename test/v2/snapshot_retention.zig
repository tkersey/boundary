const std = @import("std");
const d = @import("boundary_data");
pub fn main(init: std.process.Init) !void {
    var nodes: [128]d.process_state.Node = undefined;
    const value: d.graph.Value = .{ .schema = 0, .body = .{ .blob = .{ .id = 0 } } };
    for (&nodes, 0..) |*node, index| node.* = .{ .record = .{ .environment = .{
        .values = &.{value},
        .tail = .{ .id = (index + 1) % nodes.len },
    } } };
    const state: d.process_state.State = .{ .program_identity = .{0} ** 32, .status = .active, .roots = .{ .current = .{ .id = 0 } }, .nodes = &nodes, .blobs = &.{.{ .schema = 0, .bytes = "retained immutable payload" }} };
    var tracked = std.testing.FailingAllocator.init(init.gpa, .{});
    var result = try d.graph_order.canonicalize(tracked.allocator(), state, null);
    const retained = tracked.allocated_bytes - tracked.freed_bytes;
    const bytes = try d.state_image.emit(init.gpa, result.state);
    defer init.gpa.free(bytes);
    result.deinit();
    std.debug.assert(tracked.allocated_bytes == tracked.freed_bytes);
    std.debug.print("retained={d} bytes={d} digest={x}\n", .{ retained, bytes.len, d.wire.digest(bytes) });
}
