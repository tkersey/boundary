//! Exercise the actual higher-order authoring, lowering and image publication path.
const std = @import("std");
const boundary = @import("boundary");
const workload = @import("workload");
fn construct(allocator: std.mem.Allocator) !void {
    var builder = boundary.computation.Builder.init(allocator);
    defer builder.deinit();
    const module = try workload.emitWorkload(&builder, .hyper);
    var compiled = try boundary.computation.lower(allocator, module);
    defer compiled.deinit();
    const bytes = try allocator.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer allocator.free(bytes);
    _ = try compiled.encode(allocator, bytes);
    var decoded = try boundary.data.program_image.decode(allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqual(compiled.program.functions.len, decoded.program.functions.len);
}
test "hyperfunction construction lowering and publication release every partial allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, construct, .{});
}
