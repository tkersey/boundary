// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const testing = std.testing;
const pass = @import("coalescing.zig");
const image = @import("program_image.zig");
const fixture = @import("coalescing_witness_tests.zig").original;

fn bytes(program: @import("activation.zig").Program) ![]u8 {
    const result = try testing.allocator.alloc(u8, try image.encodedLength(program));
    errdefer testing.allocator.free(result);
    _ = try image.encode(testing.allocator, program, result);
    return result;
}

test "coalescing selects exact economical candidate to an idempotent fixed point" {
    var stats: pass.Statistics = .{};
    var full = try pass.run(testing.allocator, fixture, .{ .mode = .safe, .statistics = &stats });
    defer full.deinit();
    try testing.expectEqual(pass.Outcome.applied, stats.outcome);
    try testing.expectEqual(@as(usize, 1), stats.extraction_rounds);
    try testing.expectEqual(@as(usize, 2), full.program.functions.len);
    try testing.expect(stats.selected.bytes < stats.baseline.bytes);
    var again_stats: pass.Statistics = .{};
    var again = try pass.run(
        testing.allocator,
        full.program,
        .{ .mode = .safe, .statistics = &again_stats },
    );
    defer again.deinit();
    try testing.expectEqual(pass.Outcome.no_change, again_stats.outcome);
    const first_bytes = try bytes(full.program);
    defer testing.allocator.free(first_bytes);
    const second_bytes = try bytes(again.program);
    defer testing.allocator.free(second_bytes);
    try testing.expectEqualSlices(u8, first_bytes, second_bytes);
}

test "coalescing work limit after an intermediate selection returns original baseline" {
    var stats: pass.Statistics = .{};
    var measured = try pass.run(
        testing.allocator,
        fixture,
        .{ .mode = .safe, .statistics = &stats },
    );
    defer measured.deinit();
    try testing.expect(stats.first_selected_work > 0);
    var off = try pass.run(testing.allocator, fixture, .{});
    defer off.deinit();
    const baseline = try bytes(off.program);
    defer testing.allocator.free(baseline);
    for ([_]u64{ 0, stats.first_selected_work }) |limit| {
        var limited_stats: pass.Statistics = .{};
        var limited = try pass.run(
            testing.allocator,
            fixture,
            .{ .mode = .safe, .work_limit = limit, .statistics = &limited_stats },
        );
        defer limited.deinit();
        try testing.expectEqual(pass.Outcome.work_limit, limited_stats.outcome);
        try testing.expectEqual(@as(usize, 0), limited_stats.extraction_rounds);
        const actual = try bytes(limited.program);
        defer testing.allocator.free(actual);
        try testing.expectEqualSlices(u8, baseline, actual);
    }
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var result = try pass.run(allocator, fixture, .{ .mode = .safe });
    defer result.deinit();
    try testing.expectEqual(@as(usize, 2), result.program.functions.len);
}

test "coalescing fixed point releases all owners at every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationCase, .{});
}
