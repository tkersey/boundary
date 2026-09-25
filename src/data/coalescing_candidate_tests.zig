// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const testing = std.testing;
const discovery = @import("coalescing_discovery.zig");
const candidate = @import("coalescing_candidate.zig");
const graph = @import("coalescing_graph.zig");
const ir = @import("activation.zig");
const r = @import("relocation.zig");
const image = @import("program_image.zig");
const fixture = @import("coalescing_witness_tests.zig").original;

fn candidateCase(allocator: std.mem.Allocator) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var input_owner = std.heap.ArenaAllocator.init(allocator);
    defer input_owner.deinit();
    var original_facts = try @import("activation_ownership.zig").analyze(allocator, fixture);
    original_facts.deinit();
    const baseline = try r.ownReachable(input_owner.allocator(), scratch.allocator(), fixture);
    var work: graph.Work = .{};
    const opportunities = try discovery.analyze(scratch.allocator(), baseline.program, &work);
    var full = try candidate.build(
        allocator,
        scratch.allocator(),
        baseline.program,
        opportunities,
        .full,
        &work,
    );
    defer full.deinit();
    try testing.expectEqual(@as(usize, 2), full.program.functions.len);
    try testing.expect(full.bytes < try image.encodedLength(baseline.program));
    const buffer = try allocator.alloc(u8, full.bytes);
    defer allocator.free(buffer);
    try testing.expectEqual(full.bytes, (try image.encode(allocator, full.program, buffer)).len);
    var descriptions = try candidate.build(
        allocator,
        scratch.allocator(),
        baseline.program,
        opportunities,
        .descriptions,
        &work,
    );
    defer descriptions.deinit();
    try testing.expectEqual(@as(usize, 3), descriptions.program.functions.len);
    try testing.expectEqual(try image.encodedLength(baseline.program), descriptions.bytes);
}

test "coalescing candidate shares whole code and independently admits both profiles" {
    try candidateCase(testing.allocator);
}

test "coalescing candidate owns selected storage after source and scratch release" {
    var full = result: {
        var scratch = std.heap.ArenaAllocator.init(testing.allocator);
        defer scratch.deinit();
        var work: graph.Work = .{};
        const opportunities = try discovery.analyze(scratch.allocator(), fixture, &work);
        break :result try candidate.build(
            testing.allocator,
            scratch.allocator(),
            fixture,
            opportunities,
            .full,
            &work,
        );
    };
    defer full.deinit();
    // Scratch correspondence is deliberately not accessed after the arena dies.
    var checked = try @import("activation_ownership.zig").analyze(testing.allocator, full.program);
    defer checked.deinit();
    try testing.expectEqual(@as(usize, 2), full.program.functions.len);
}

test "coalescing candidate allocation failures leave no partially published owner" {
    try testing.checkAllAllocationFailures(testing.allocator, candidateCase, .{});
}

test "coalescing candidate keeps pinned authority functions separate" {
    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    var work: graph.Work = .{};
    var program = fixture;
    program.scopes.resources = &.{.{
        .representation = 0,
        .introducers = &.{0},
        .eliminators = &.{1},
    }};
    const opportunities = try discovery.analyze(scratch.allocator(), program, &work);
    const map = try discovery.correspondence(
        scratch.allocator(),
        program,
        opportunities,
        .full,
        &work,
    );
    try testing.expectEqualSlices(
        ir.Id,
        &.{ 0, 1, 2 },
        map.representatives[@intFromEnum(r.Kind.function)],
    );
}
