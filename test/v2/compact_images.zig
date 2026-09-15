//! Public builder to packed image to exact legacy logical projection.
const std = @import("std");
const boundary = @import("boundary");
const data = boundary.data_v2;

fn pooledFailures(allocator: std.mem.Allocator, program: data.program.Program) !void {
    var output = [_]u8{0xa5} ** 4096;
    const encoded = data.compact_image.encode(allocator, program, &output) catch |err| {
        for (output) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
        return err;
    };
    var decoded = try data.compact_image.decode(allocator, encoded);
    defer decoded.deinit();
    try std.testing.expectEqualDeep(program, decoded.program);
}

test "pooled decoder backing and temporary reference marks survive allocation failure" {
    var b = boundary.source.Builder.init(std.testing.allocator);
    defer b.deinit();
    var compiled = try boundary.program.compile(std.testing.allocator, try @import("compact_fixtures.zig").variedMixed(&b, 8, .{ .seed = 11 }));
    defer compiled.deinit();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, pooledFailures, .{compiled.program});
}

fn check(program: data.program.Program, must_shrink: bool) !void {
    const allocator = std.testing.allocator;
    const legacy = try allocator.alloc(u8, try data.image.encodedLength(program));
    defer allocator.free(legacy);
    _ = try data.image.encode(allocator, program, legacy);
    const compact = try allocator.alloc(u8, try data.compact_image.encodedLength(allocator, program));
    defer allocator.free(compact);
    _ = try data.compact_image.encode(allocator, program, compact);
    try std.testing.expect(compact.len <= legacy.len);
    if (must_shrink) try std.testing.expect(compact.len < legacy.len);
    var decoded = try data.compact_image.decode(allocator, compact);
    defer decoded.deinit();
    try std.testing.expectEqualDeep(program, decoded.program);
    try std.testing.expectEqual(try data.image.identity(program), try data.image.identity(decoded.program));
    const restored = try allocator.alloc(u8, legacy.len);
    defer allocator.free(restored);
    _ = try data.image.encode(allocator, decoded.program, restored);
    try std.testing.expectEqualSlices(u8, legacy, restored);
    const repeated = try allocator.alloc(u8, compact.len);
    defer allocator.free(repeated);
    _ = try data.compact_image.encode(allocator, decoded.program, repeated);
    try std.testing.expectEqualSlices(u8, compact, repeated);
    @memset(compact, 0xa5);
    try std.testing.expectEqualDeep(program, decoded.program);
    @memset(repeated, 0xa5);
    try std.testing.expectError(error.Capacity, data.compact_image.encode(allocator, program, repeated[0 .. repeated.len - 1]));
    for (repeated) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
}

test "compact public codec preserves installation programs through integer widths" {
    for ([_]usize{ 1, 8, 64, 127, 128 }) |count| {
        var builder = boundary.computation.Builder.init(std.testing.allocator);
        defer builder.deinit();
        var compiled = try boundary.program.compile(std.testing.allocator, try boundary.source.examples.installations(&builder, count));
        defer compiled.deinit();
        try check(compiled.program, count >= 8);
    }
}

test "compact public codec handles capture payload and residual requests" {
    inline for (.{ boundary.source.examples.blobCapture, boundary.source.examples.queensDfs }) |example| {
        var builder = boundary.computation.Builder.init(std.testing.allocator);
        defer builder.deinit();
        var compiled = try boundary.program.compile(std.testing.allocator, try example(&builder));
        defer compiled.deinit();
        try check(compiled.program, false);
    }
}

test "heterogeneous growing interfaces, permutations and copied operands remain exact" {
    for (0..3) |rotation| for ([_]bool{ false, true }) |reverse| {
        var builder = boundary.computation.Builder.init(std.testing.allocator);
        defer builder.deinit();
        var compiled = try boundary.program.compile(std.testing.allocator, try @import("compact_fixtures.zig").mixed(&builder, 64, rotation, reverse));
        defer compiled.deinit();
        try check(compiled.program, true);
    };
}

test "unsuitable metadata uses byte-identical BPI2 fallback" {
    const allocator = std.testing.allocator;
    var b = boundary.source.Builder.init(allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    var result = integer;
    const depth = 64;
    for (0..depth) |_| result = try b.schema(.{ .product = &.{ integer, boolean, result, boolean, integer } });
    const bytes = try b.allocator().alloc(u8, 8 + 18 * depth);
    @memset(bytes, 0);
    const entry = try b.declare(&.{}, result, &.{}, &.{});
    try b.define(entry, try b.pure(try b.literal(.{ .schema = result, .bytes = bytes })));
    var compiled = try boundary.program.compile(allocator, b.module(entry, unit));
    defer compiled.deinit();
    const length = try data.compact_image.encodedLength(allocator, compiled.program);
    const output = try allocator.alloc(u8, length);
    defer allocator.free(output);
    const encoded = try data.compact_image.encode(allocator, compiled.program, output);
    try std.testing.expectEqualStrings("ABL_BPI2", encoded[0..8]);
    try check(compiled.program, false);
}

test "nonperiodic schemas, operand order, variable order and copies vary independently" {
    for ([_]u64{ 11, 991 }) |seed| for ([_]bool{ false, true }) |operands| {
        for ([_]bool{ false, true }) |declarations| for ([_]usize{ 0, 3 }) |copies| {
            var b = boundary.source.Builder.init(std.testing.allocator);
            defer b.deinit();
            var compiled = try boundary.program.compile(std.testing.allocator, try @import("compact_fixtures.zig").variedMixed(&b, 64, .{
                .seed = seed,
                .reverse_operands = operands,
                .reverse_declarations = declarations,
                .copies = copies,
            }));
            defer compiled.deinit();
            try check(compiled.program, true);
        };
    };
}
