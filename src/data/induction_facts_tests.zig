const std = @import("std");
const ir = @import("activation.zig");
const facts = @import("induction_facts.zig");
const loops = @import("loop_regions.zig");
const own = @import("activation_ownership.zig");
const base = @import("loop_motion_tests.zig").counted;
const a = std.testing.allocator;
fn derive(allocator: std.mem.Allocator, program: ir.Program) !?facts.Certificate {
    var admitted = try own.analyze(allocator, program);
    defer admitted.deinit();
    var budget: loops.Budget = .{ .remaining = 2_000_000 };
    const graph = (try loops.Graph.init(allocator, program, 0, &budget)).?;
    const outside = try graph.reachAvoid(graph.local[1], &budget);
    const dominated = try allocator.alloc(bool, graph.blocks.len);
    for (dominated, 0..) |*v, i| v.* = graph.reachable[i] and !outside[i];
    const members = (try graph.region(graph.local[1], dominated, &budget)).?;
    return facts.derive(allocator, program, graph, members, 1, &budget);
}
test "unit induction is finite up to the full unsigned limit" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const proof = (try derive(arena.allocator(), base)).?;
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), proof.limit_upper);
    try std.testing.expectEqual(@as(u64, 3), proof.index);
    try std.testing.expectEqual(@as(usize, 2), proof.latch);
    try std.testing.expect(proof.actual_length == null);
}
test "zero stride and wraparound strides do not prove unit induction" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var original = base;
    var constants = base.constants[0..3].*;
    constants[1].bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 };
    original.constants = &constants;
    try std.testing.expect(try derive(arena.allocator(), original) == null);
    constants[1].bytes = &.{ 2, 0, 0, 0, 0, 0, 0, 0 };
    try std.testing.expect(try derive(arena.allocator(), original) == null);
}
test "signed counters do not acquire an unsigned induction certificate" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var original = base;
    var schemas = base.schemas[0..3].*;
    schemas[0] = .i64;
    original.schemas = &schemas;
    try std.testing.expect(try derive(arena.allocator(), original) == null);
}
