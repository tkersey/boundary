//! Migration witnesses exercise the actual logical-record traversal.
const std = @import("std");
const record = @import("record.zig");
const equal = @import("record_equal.zig").equal;
const wire = @import("wire.zig");

fn checkLogicalBits(values: [2]u9) !void {
    const expected = @as(u18, values[0]) | (@as(u18, values[1]) << 9);
    const scalar: u18 = @bitCast(values);
    try std.testing.expectEqual(expected, scalar);
    const vector: @Vector(2, u9) = values;
    try std.testing.expectEqual(expected, @as(u18, @bitCast(vector)));
    const Packed = packed struct(u18) { first: u9, second: u9 };
    const packed_value: Packed = @bitCast(scalar);
    try std.testing.expectEqual(values[0], packed_value.first);
    try std.testing.expectEqual(values[1], packed_value.second);
    try std.testing.expectEqualSlices(u9, &values, &@as([2]u9, @bitCast(scalar)));
}

test "Z17 logical array vector and packed bits are independent of memory padding" {
    const cases = [_][2]u9{ .{ 0, 0 }, .{ 511, 511 }, .{ 0x101, 0x1fe }, .{ 1, 256 } };
    comptime for (cases) |values| try checkLogicalBits(values);
    var runtime_cases = cases;
    std.mem.doNotOptimizeAway(&runtime_cases);
    for (runtime_cases) |values| try checkLogicalBits(values);
    try std.testing.expectEqual(@as(usize, 4), @sizeOf([2]u9));
    try std.testing.expectEqual(@as(usize, 18), @bitSizeOf([2]u9));
    const empty: [0]u9 = @bitCast(@as(u0, 0));
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

test "Z17 extern memory inspection is distinct from canonical fixed wire bytes" {
    const Pair = extern struct { first: u8, second: u8 };
    const Memory = extern union { fields: Pair, scalar: u16 };
    var memory: Memory = .{ .fields = .{ .first = 0x12, .second = 0xab } };
    std.mem.doNotOptimizeAway(&memory);
    // All bytes are initialized; the live, aligned extern union owns both views.
    const native_expected: u16 = switch (std.lang.Endian.native) {
        .little => 0xab12,
        .big => 0x12ab,
    };
    try std.testing.expectEqual(native_expected, memory.scalar);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0xab }, std.mem.asBytes(&memory.fields));
    var bytes: [2]u8 = undefined;
    var writer = wire.Writer{ .output = &bytes };
    try writer.fixed(u16, 0xab12);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0xab }, &bytes);
    var reader = wire.Reader{ .input = &bytes };
    try std.testing.expectEqual(@as(u16, 0xab12), try reader.fixed(u16));
}

test "Z17 empty records tuples optional values and arrays retain declaration-order bytes" {
    const Product = struct {
        empty: struct {},
        tuple: struct { u3, ?u16 },
        @"wire bytes": [2]u8,
    };
    const value: Product = .{ .empty = .{}, .tuple = .{ 5, 300 }, .@"wire bytes" = .{ 0x80, 0xff } };
    var bytes: [32]u8 = undefined;
    var writer = wire.Writer{ .output = &bytes };
    try record.write(Product, value, &writer);
    const golden = [_]u8{ 5, 1, 0xac, 2, 0x80, 0xff };
    try std.testing.expectEqualSlices(u8, &golden, bytes[0..writer.position]);
    var reader = wire.Reader{ .input = &golden };
    const decoded = try record.read(Product, &reader, std.testing.allocator);
    try std.testing.expect(equal(Product, value, decoded));
    try std.testing.expectEqual(golden.len, reader.position);
    var empty_writer = wire.Writer{ .output = &bytes };
    try record.write([0]u8, .{}, &empty_writer);
    try std.testing.expectEqual(@as(usize, 0), empty_writer.position);
}

test "Z17 union declaration order is independent of explicit wire tag values" {
    const Tag = enum(u8) { later = 11, earlier = 3 };
    const Value = union(Tag) { later: void, earlier: u16 };
    var bytes: [16]u8 = undefined;
    var writer = wire.Writer{ .output = &bytes };
    try record.write(Value, .{ .earlier = 9 }, &writer);
    try std.testing.expectEqualSlices(u8, &.{ 3, 9 }, bytes[0..writer.position]);
    var reader = wire.Reader{ .input = &.{ 3, 9 } };
    try std.testing.expectEqual(@as(u16, 9), (try record.read(Value, &reader, std.testing.allocator)).earlier);
    var wrong = wire.Reader{ .input = &.{7} };
    try std.testing.expectError(error.InvalidTag, record.read(Value, &wrong, std.testing.allocator));
    var truncated = wire.Reader{ .input = &.{3} };
    try std.testing.expectError(error.Truncated, record.read(Value, &truncated, std.testing.allocator));
}

test "Z17 structural equality traverses distinct slices and preserves numeric float equality" {
    const Product = struct { values: []const u64, optional: ?u8 };
    const first = [_]u64{ 1, 2 };
    var second = first;
    const left: Product = .{ .values = &first, .optional = 3 };
    const right: Product = .{ .values = &second, .optional = 3 };
    try std.testing.expect(equal(Product, left, right));
    second[1] = 4;
    try std.testing.expect(!equal(Product, left, right));
    const nan = [_]f64{std.math.nan(f64)};
    try std.testing.expect(!equal([]const f64, &nan, &nan));
    try std.testing.expect(equal(f64, 0.0, -0.0));
}
