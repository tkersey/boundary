// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const sets = @import("analysis_sets.zig");
const testing = std.testing;

test "set overlays share immutable roots and isolate all eight-bit operations" {
    var base: sets.Pool = .{ .allocator = testing.allocator, .limit = 8 };
    defer base.deinit();
    const prefix = try base.run(0, 4);
    const frozen = try base.readOnly();
    const count = frozen.nodeCount();
    const visits = base.visits;
    var overlay = sets.Pool.overlay(testing.allocator, frozen);
    defer overlay.deinit();
    var roots: [256]sets.Root = @splat(sets.empty);
    for (&roots, 0..) |*root, bits| for (0..8) |member| {
        if ((bits & (@as(usize, 1) << @intCast(member))) != 0) root.* = try overlay.insert(root.*, member);
    };
    try testing.expectEqual(prefix, roots[15]);
    for (roots, 0..) |left, a| for (roots, 0..) |right, b| {
        try testing.expectEqual(roots[a | b], try overlay.unite(left, right));
        try testing.expectEqual(roots[a & b], try overlay.intersect(left, right));
        try testing.expectEqual(roots[a & (~b & 255)], try overlay.difference(left, right));
    };
    try testing.expectEqual(count, frozen.nodeCount());
    try testing.expectEqual(visits, base.visits);
    try testing.expectError(error.InvalidReference, overlay.readOnly());
    var sibling = sets.Pool.overlay(testing.allocator, frozen);
    defer sibling.deinit();
    try testing.expectEqual(0, sibling.nodes.items.len);
    try testing.expectEqual(@as(u8, 15), mask(&sibling, prefix));
}

test "set overlay reuse needs no allocation and failure leaves the base intact" {
    var base: sets.Pool = .{ .allocator = testing.allocator, .limit = 8 };
    defer base.deinit();
    const prefix = try base.run(0, 4);
    var empty_buffer: [0]u8 = .{};
    var buffer = std.heap.FixedBufferAllocator.init(&empty_buffer);
    var overlay = sets.Pool.overlay(buffer.allocator(), try base.readOnly());
    defer overlay.deinit();
    try testing.expectEqual(prefix, try overlay.run(0, 4));
    try testing.expectError(error.OutOfMemory, overlay.insert(prefix, 7));
    try testing.expectEqual(0, overlay.nodes.items.len);
    try testing.expectEqual(@as(u8, 15), mask(&overlay, prefix));
    try testing.expectEqual(@as(u8, 15), mask(&base, prefix));
}

fn mask(pool: *sets.Pool, root: sets.Root) u8 {
    var result: u8 = 0;
    var iterator = pool.iterator(root);
    while (iterator.next()) |member| result |= @as(u8, 1) << @intCast(member);
    return result;
}

test "analysis sets agree with every pair of eight-bit sets" {
    var pool: sets.Pool = .{ .allocator = testing.allocator, .limit = 8 };
    defer pool.deinit();
    var roots: [256]sets.Root = @splat(sets.empty);
    for (&roots, 0..) |*root, bits| {
        for (0..8) |member| if ((bits & (@as(usize, 1) << @intCast(member))) != 0) {
            root.* = try pool.insert(root.*, member);
        };
        try testing.expectEqual(@as(u8, @intCast(bits)), mask(&pool, root.*));
    }
    for (roots, 0..) |left, a| {
        for (roots, 0..) |right, b| {
            try testing.expectEqual(roots[a | b], try pool.unite(left, right));
            try testing.expectEqual(roots[a & b], try pool.intersect(left, right));
            try testing.expectEqual(roots[a & (~b & 255)], try pool.difference(left, right));
        }
        for (0..8) |member| {
            const bit = @as(usize, 1) << @intCast(member);
            try testing.expectEqual(roots[a & ~bit], try pool.remove(left, member));
            try testing.expectEqual((a & bit) != 0, pool.contains(left, member));
        }
    }
}

test "analysis sets encode every monotonic prefix with bounded incremental nodes" {
    var pool: sets.Pool = .{ .allocator = testing.allocator, .limit = 4096 };
    defer pool.deinit();
    var root = sets.empty;
    for (0..4096) |member| {
        const before = pool.nodes.items.len;
        root = try pool.insert(root, member);
        try testing.expect(pool.nodes.items.len - before <= 2);
        try testing.expectEqual(member + 1, pool.count(root));
    }
    try testing.expect(pool.visits <= 4096);
    const original = root;
    for (0..4096) |member| root = try pool.remove(root, member);
    try testing.expectEqual(sets.empty, root);
    try testing.expectEqual(4096, pool.count(original));
}

test "analysis sets handle high IDs and bounds without input-sized recursion" {
    var pool: sets.Pool = .{ .allocator = testing.allocator, .limit = std.math.maxInt(u64) };
    defer pool.deinit();
    const high = pool.limit - 1;
    const all = try pool.run(0, pool.limit);
    const middle = try pool.remove(all, @as(u64, 1) << 63);
    try testing.expectEqual(pool.limit - 1, pool.count(middle));
    try testing.expect(!pool.contains(middle, @as(u64, 1) << 63));
    try testing.expect(pool.contains(middle, high));
    try testing.expectError(error.InvalidReference, pool.insert(all, pool.limit));
    try testing.expectEqual(all, try pool.insert(middle, @as(u64, 1) << 63));
}

fn failureCase(allocator: std.mem.Allocator) !void {
    var pool: sets.Pool = .{ .allocator = allocator, .limit = 32 };
    defer pool.deinit();
    const before = try pool.run(0, 16);
    const changed = pool.remove(before, 7) catch |err| {
        try testing.expectEqual(16, pool.count(before));
        try testing.expect(pool.contains(before, 7));
        return err;
    };
    try testing.expectEqual(15, pool.count(changed));
    try testing.expectEqual(16, pool.count(before));
    const bytes = try pool.materialize(allocator, changed);
    defer allocator.free(bytes);
    try testing.expectEqual(15, bytes.len);
}

test "analysis sets preserve prior roots and ownership through allocation failures" {
    try testing.checkAllAllocationFailures(testing.allocator, failureCase, .{});
}

test "low-word projection matches membership without allocating or changing shared roots" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    var base: sets.Pool = .{ .allocator = failing.allocator(), .limit = std.math.maxInt(u64) };
    defer base.deinit();
    for (0..81) |low| for (low..81) |high| {
        const root = try base.run(low, high);
        var expected: u64 = 0;
        for (0..64) |bit| if (low <= bit and bit < high) {
            expected |= @as(u64, 1) << @intCast(bit);
        };
        try testing.expectEqual(expected, base.lowWord(root));
    };
    const far = try base.run(60, std.math.maxInt(u64));
    const frozen = try base.readOnly();
    const base_nodes = frozen.nodeCount();
    var overlay = sets.Pool.overlay(failing.allocator(), frozen);
    defer overlay.deinit();
    const members = [_]u64{ 0, 1, 7, 31, 32, 63, 64, std.math.maxInt(u64) - 1 };
    var roots: [256]sets.Root = undefined;
    for (&roots, 0..) |*root, subset| {
        root.* = sets.empty;
        for (members, 0..) |member, bit| if (subset & (@as(usize, 1) << @intCast(bit)) != 0) {
            root.* = try overlay.insert(root.*, member);
        };
    }
    var ladder = try overlay.insert(sets.empty, 0);
    for (0..64) |bit| ladder = try overlay.insert(ladder, @as(u64, 1) << @intCast(bit));
    const overlay_nodes = overlay.nodes.items.len;
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(@as(u64, 0x100010117), overlay.lowWord(ladder));
    try testing.expectEqual(@as(u64, 0xf000000000000000), overlay.lowWord(far));
    for (roots) |root| {
        var expected: u64 = 0;
        for (0..64) |bit| if (overlay.contains(root, bit)) {
            expected |= @as(u64, 1) << @intCast(bit);
        };
        try testing.expectEqual(expected, overlay.lowWord(root));
    }
    try testing.expect(!failing.has_induced_failure);
    try testing.expectEqual(base_nodes, frozen.nodeCount());
    try testing.expectEqual(overlay_nodes, overlay.nodes.items.len);
}

test "canonical word leaves preserve all cross-word subsets and high-ID operations" {
    const maximum = std.math.maxInt(u64);
    const offsets = [_]u64{ 0, 31, 63, 64, 65, 95, 127, 128 };
    for ([_]u64{ 0, 1, 64, maximum - 256 }) |base| {
        var pool: sets.Pool = .{ .allocator = testing.allocator, .limit = maximum };
        defer pool.deinit();
        var roots: [256]sets.Root = @splat(sets.empty);
        for (&roots, 0..) |*root, bits| {
            for (offsets, 0..) |offset, bit| if (bits & (@as(usize, 1) << @intCast(bit)) != 0) {
                root.* = try pool.insert(root.*, base + offset);
            };
            var reverse = sets.empty;
            var index = offsets.len;
            while (index > 0) {
                index -= 1;
                if (bits & (@as(usize, 1) << @intCast(index)) != 0)
                    reverse = try pool.insert(reverse, base + offsets[index]);
            }
            try testing.expectEqual(root.*, reverse);
            var iterator = pool.iterator(root.*);
            for (offsets, 0..) |offset, bit| {
                const present = bits & (@as(usize, 1) << @intCast(bit)) != 0;
                try testing.expectEqual(present, pool.contains(root.*, base + offset));
                if (present) try testing.expectEqual(base + offset, iterator.next().?);
            }
            try testing.expect(iterator.next() == null);
        }
        const frozen = try pool.readOnly();
        const node_count = frozen.nodeCount();
        var overlay = sets.Pool.overlay(testing.allocator, frozen);
        defer overlay.deinit();
        for (roots, 0..) |left, a| for (roots, 0..) |right, b| {
            try testing.expectEqual(roots[a | b], try overlay.unite(left, right));
            try testing.expectEqual(roots[a & b], try overlay.intersect(left, right));
            try testing.expectEqual(roots[a & (~b & 255)], try overlay.difference(left, right));
        };
        try testing.expectEqual(node_count, frozen.nodeCount());
        try testing.expectEqual(0, overlay.nodes.items.len);
    }
}

test "canonical set node does not grow for word leaves" {
    const pool: sets.Pool = .{ .allocator = testing.allocator, .limit = 8 };
    const Node = @typeInfo(@TypeOf(pool.nodes.items)).pointer.child;
    try testing.expectEqual(3 * @sizeOf(u64) + 2 * @sizeOf(usize), @sizeOf(Node));
}
