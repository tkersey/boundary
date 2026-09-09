//! Independent wire records and mutations, with admitted valid counterparts.
const std = @import("std");
const image = @import("image.zig");
const wire = @import("wire.zig");
const p = @import("program.zig");
const valid = @import("tests.zig").example;
const allocator = std.testing.allocator;

// This is a complete scalar image written from the published field/tag table,
// independently of image.encode and the generic record writer.
const sections: [9][]const u8 = .{
    &.{ 1, 0, 0, 0 }, // profile, entry, result, failure
    &.{ 1, 9 }, // one u64 schema
    &.{ 1, 0, 8, 42, 0, 0, 0, 0, 0, 0, 0 },
    &.{0},
    &.{ 1, 0, 0, 0, 0, 0 }, // one function
    &.{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0 }, // one constant and return
    &.{0},
    &.{ 0, 0, 0 }, // captures, regions, resources
    &.{0},
};
fn independent(parts: [9][]const u8, output: []u8) []u8 {
    var length: usize = 48;
    for (parts) |part| length += part.len;
    std.debug.assert(length <= output.len);
    @memcpy(output[0..8], "ABL_BPI2");
    std.mem.writeInt(u16, output[8..10], 2, .little);
    std.mem.writeInt(u16, output[10..12], 0, .little);
    std.mem.writeInt(u64, output[12..20], length - 20, .little);
    output[20] = 9;
    var offset: u8 = 0;
    for (parts, 0..) |part, index| {
        output[21 + index * 3] = @intCast(index + 1);
        output[22 + index * 3] = offset;
        output[23 + index * 3] = @intCast(part.len);
        offset += @intCast(part.len);
    }
    var cursor: usize = 48;
    for (parts) |part| {
        @memcpy(output[cursor..][0..part.len], part);
        cursor += part.len;
    }
    return output[0..length];
}
fn rejected(bytes: []const u8) !void {
    if (image.decode(allocator, bytes)) |result| {
        var decoded = result;
        decoded.deinit();
        return error.ExpectedRejection;
    } else |err| try std.testing.expect(err != error.OutOfMemory and err != error.Capacity);
}

test "independently written BPI2 agrees with the canonical encoder" {
    var buffer: [256]u8 = undefined;
    const bytes = independent(sections, &buffer);
    var decoded = try image.decode(allocator, bytes);
    defer decoded.deinit();
    var encoded: [256]u8 = undefined;
    try std.testing.expectEqualSlices(u8, bytes, try image.encode(allocator, valid, &encoded));
    for (0..bytes.len) |length| try rejected(bytes[0..length]);
}

test "directories, overflowing counts, nonminimal integers and executable tags reject" {
    var buffer: [256]u8 = undefined;
    const bytes = independent(sections, &buffer);
    for ([_]struct { offset: usize, value: u8 }{
        .{ .offset = 20, .value = 8 }, // missing directory section
        .{ .offset = 21, .value = 2 }, // duplicate/out-of-order section tag
        .{ .offset = 22, .value = 1 }, // gap before content
        .{ .offset = 23, .value = 3 }, // undersized section
        .{ .offset = 47, .value = 2 }, // oversized final section
        .{ .offset = 48, .value = 2 }, // unsupported profile
    }) |change| {
        _ = independent(sections, &buffer);
        buffer[change.offset] = change.value;
        try rejected(bytes);
    }
    for ([_][]const u8{ &.{ 0x81, 0x00, 9 }, &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x02 }, &.{ 1, 48 }, &.{ 127, 9 } }) |schemas| {
        var parts = sections;
        parts[1] = schemas;
        try rejected(independent(parts, &buffer));
    }
    var parts = sections;
    parts[5] = &.{ 1, 0, 0, 1, 48, 0, 0, 0, 0, 0, 0 }; // unknown opcode
    try rejected(independent(parts, &buffer));
    parts[5] = &.{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 18 }; // unknown terminator
    try rejected(independent(parts, &buffer));
}

test "unproductive schemas, malformed UTF-8 values and unresolved code/capture references reject" {
    var buffer: [256]u8 = undefined;
    var parts = sections;
    parts[1] = &.{ 1, 12, 1, 0 }; // unguarded product recursion
    try rejected(independent(parts, &buffer));
    parts = sections;
    parts[1] = &.{ 1, 11 }; // text
    parts[2] = &.{ 1, 0, 2, 1, 0xff }; // canonical-length text with invalid UTF-8
    try rejected(independent(parts, &buffer));
    parts = sections;
    parts[2] = &.{ 1, 0, 9, 42, 0, 0, 0, 0, 0, 0, 0, 0 }; // trailing value byte
    try rejected(independent(parts, &buffer));
    parts = sections;
    parts[4] = &.{ 1, 99, 0, 0, 0, 0 }; // unresolved function entry
    try rejected(independent(parts, &buffer));
    parts = sections;
    parts[5] = &.{ 1, 99, 0, 1, 0, 0, 0, 0, 0, 0, 0 }; // wrong block owner
    try rejected(independent(parts, &buffer));
    parts[5] = &.{ 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 99 }; // unresolved returned register
    try rejected(independent(parts, &buffer));
    parts = sections;
    parts[8] = &.{ 1, 0, 99, 0 }; // unresolved constructor capture
    try rejected(independent(parts, &buffer));
    parts = sections;
    parts[7] = &.{ 0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0 }; // impossible canonical region inventory
    try rejected(independent(parts, &buffer));
}

test "every image emission allocation and output capacity failure is transactional" {
    const Emission = struct {
        fn run(failing: std.mem.Allocator) !void {
            var output = [_]u8{0xa5} ** 256;
            const encoded = image.encode(failing, valid, &output) catch |err| {
                try std.testing.expect(std.mem.allEqual(u8, &output, 0xa5));
                return err;
            };
            var decoded = try image.decode(allocator, encoded);
            defer decoded.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(allocator, Emission.run, .{});
    const length = try image.encodedLength(valid);
    var buffer = [_]u8{0xa5} ** 256;
    for (0..length) |size| {
        try std.testing.expectError(error.Capacity, image.encode(allocator, valid, buffer[0..size]));
        try std.testing.expect(std.mem.allEqual(u8, &buffer, 0xa5));
    }
    const Decoding = struct {
        fn run(failing: std.mem.Allocator, input: []const u8) !void {
            const before = wire.digest(input);
            defer std.debug.assert(std.mem.eql(u8, &before, &wire.digest(input)));
            var result = try image.decode(failing, input);
            defer result.deinit();
        }
    };
    const bytes = independent(sections, &buffer);
    try std.testing.checkAllAllocationFailures(allocator, Decoding.run, .{bytes});
}

test "unused nominal region ordinals normalize without allocating their numeric range" {
    var logical = valid;
    logical.scopes.region_count = std.math.maxInt(p.Id);
    try @import("admission.zig").program(allocator, logical);
    var normalized = try @import("canonical.zig").normalize(allocator, logical);
    defer normalized.deinit();
    try std.testing.expectEqual(@as(p.Id, 0), normalized.program.scopes.region_count);
    var original_bytes: [256]u8 = undefined;
    var normalized_bytes: [256]u8 = undefined;
    try std.testing.expectEqualSlices(u8, try image.encode(allocator, valid, &original_bytes), try image.encode(allocator, normalized.program, &normalized_bytes));
    try std.testing.expectError(error.NonCanonical, @import("canonical.zig").require(allocator, logical));
}
