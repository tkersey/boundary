// Copyright (c) 2026 Boundary contributors. MIT license.
//! Internal record encoding: explicit declaration order, minimal unsigned tags.
//! Only the checked logical catalog types call this module; no native layout is used.
const std = @import("std");
const wire = @import("wire.zig");
pub const Error = wire.Error || std.mem.Allocator.Error;

// A sizing sink can sum numeric sequence widths without generating each byte.
// Hashing, comparison and real output always use the original writer below.
fn measuredSequence(comptime T: type, values: []const T) wire.Error!usize {
    var total: usize = 0;
    for (values) |value| {
        const length = if (T == u64) naturalLength(value) else switch (value) {
            .slot => |id| naturalLength(@intFromEnum(std.meta.activeTag(value))) + naturalLength(id),
            .returned => naturalLength(@intFromEnum(std.meta.activeTag(value))),
        };
        total = std.math.add(usize, total, length) catch return error.InvalidLength;
    }
    return total;
}

fn naturalLength(value: u64) usize {
    return (@as(usize, 64 - @clz(value | 1)) + 6) / 7;
}

/// Traverses borrowed record storage, including nested arrays of slices, before
/// a caller-owned encoder writes its first byte. Native bytes are never encoded.
pub fn overlaps(comptime T: type, value: T, output: []const u8) bool {
    switch (@typeInfo(T)) {
        .pointer => |info| {
            if (wire.overlap(std.mem.sliceAsBytes(value), output)) return true;
            if (info.child != u8) for (value) |element| {
                if (overlaps(info.child, element, output)) return true;
            };
        },
        .array => |info| {
            if (info.child != u8) for (value) |element| {
                if (overlaps(info.child, element, output)) return true;
            };
        },
        .@"struct" => |info| inline for (info.fields) |field| {
            if (overlaps(field.type, @field(value, field.name), output)) return true;
        },
        .@"union" => |info| inline for (info.fields) |field| {
            if (std.mem.eql(u8, field.name, @tagName(value)))
                return overlaps(field.type, @field(value, field.name), output);
        },
        .optional => |info| {
            if (value) |present| return overlaps(info.child, present, output);
        },
        else => {},
    }
    return false;
}

pub fn write(comptime T: type, value: T, writer: *wire.Writer) wire.Error!void {
    switch (@typeInfo(T)) {
        .void => {},
        .bool => try writer.byte(@intFromBool(value)),
        .int => |info| {
            comptime std.debug.assert(info.signedness == .unsigned and info.bits <= 64);
            try writer.natural(value);
        },
        .@"enum" => try writer.natural(@intFromEnum(value)),
        .optional => |info| {
            try writer.byte(@intFromBool(value != null));
            if (value) |present| try write(info.child, present, writer);
        },
        .pointer => |info| {
            comptime std.debug.assert(info.size == .slice);
            try writer.natural(value.len);
            if (info.child == u64 or info.child == @import("program.zig").Argument) {
                if (writer.output == null and writer.expected == null and writer.hasher == null) {
                    writer.position = std.math.add(usize, writer.position, try measuredSequence(info.child, value)) catch return error.InvalidLength;
                    return;
                }
            }
            if (info.child == u8) return writer.put(value);
            for (value) |element| try write(info.child, element, writer);
        },
        .array => |info| {
            if (info.child == u8) return writer.put(&value);
            for (value) |element| try write(info.child, element, writer);
        },
        .@"struct" => |info| {
            inline for (info.fields) |field| try write(field.type, @field(value, field.name), writer);
        },
        .@"union" => |info| {
            try writer.natural(@intFromEnum(std.meta.activeTag(value)));
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, field.name, @tagName(value))) {
                    try write(field.type, @field(value, field.name), writer);
                    return;
                }
            }
        },
        else => @compileError("not a logical portable record: " ++ @typeName(T)),
    }
}

/// Allocations and decoded slices belong to allocator; use an invocation arena.
/// Counts are bounded by remaining bytes before allocating, including empty rows.
pub fn read(comptime T: type, reader: *wire.Reader, allocator: std.mem.Allocator) Error!T {
    return switch (@typeInfo(T)) {
        .void => {},
        .bool => switch (try reader.byte()) {
            0 => false,
            1 => true,
            else => error.InvalidTag,
        },
        .int => std.math.cast(T, try reader.natural()) orelse error.InvalidLength,
        .@"enum" => |info| blk: {
            const tag = try reader.natural();
            inline for (info.fields) |field| {
                if (tag == field.value) break :blk @enumFromInt(field.value);
            }
            break :blk error.InvalidTag;
        },
        .optional => |info| switch (try reader.byte()) {
            0 => null,
            1 => try read(info.child, reader, allocator),
            else => error.InvalidTag,
        },
        .pointer => |info| blk: {
            comptime std.debug.assert(info.size == .slice);
            const count = try reader.count();
            if (count > reader.input.len - reader.position) return error.Truncated;
            if (info.child == u8) break :blk try reader.take(count);
            const result = try allocator.alloc(info.child, count);
            for (result) |*element| element.* = try read(info.child, reader, allocator);
            break :blk result;
        },
        .array => |info| blk: {
            var result: T = undefined;
            if (info.child == u8) {
                @memcpy(&result, try reader.take(info.len));
                break :blk result;
            }
            for (&result) |*element| element.* = try read(info.child, reader, allocator);
            break :blk result;
        },
        .@"struct" => |info| blk: {
            var result: T = undefined;
            inline for (info.fields) |field| {
                @field(result, field.name) = try read(field.type, reader, allocator);
            }
            break :blk result;
        },
        .@"union" => |info| blk: {
            const tag = try reader.natural();
            inline for (info.fields) |field| {
                const declared_tag = @intFromEnum(@field(info.tag_type.?, field.name));
                if (tag == declared_tag) break :blk @unionInit(T, field.name, try read(field.type, reader, allocator));
            }
            break :blk error.InvalidTag;
        },
        else => @compileError("not a logical portable record: " ++ @typeName(T)),
    };
}

test "union decoding uses declared wire tags instead of field indexes" {
    const Tag = enum(u8) { earlier = 3, later = 11 };
    const Record = union(Tag) { earlier: u64, later };
    var bytes: [4]u8 = undefined;
    var writer: wire.Writer = .{ .output = &bytes };
    try write(Record, .{ .earlier = 42 }, &writer);
    try std.testing.expectEqualSlices(u8, &.{ 3, 42 }, bytes[0..writer.position]);
    var reader: wire.Reader = .{ .input = bytes[0..writer.position] };
    const decoded = try read(Record, &reader, std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 42), decoded.earlier);
    reader = .{ .input = &.{11} };
    try std.testing.expect(try read(Record, &reader, std.testing.allocator) == .later);
    reader = .{ .input = &.{0} };
    try std.testing.expectError(error.InvalidTag, read(Record, &reader, std.testing.allocator));
}

test "numeric sequence sizing agrees with emitted and hashed legacy bytes" {
    const Argument = @import("program.zig").Argument;
    const Row = struct { ids: []const u64, arguments: []const Argument };
    for ([_]u64{ 0, 127, 128, 16383, 16384, std.math.maxInt(u64) }) |number| {
        const value: Row = .{ .ids = &.{ number, 0, 128 }, .arguments = &.{ .{ .slot = number }, .returned, .{ .slot = 0 } } };
        var measured: wire.Writer = .{};
        try write(Row, value, &measured);
        var buffer: [128]u8 = undefined;
        var emitted: wire.Writer = .{ .output = &buffer };
        try write(Row, value, &emitted);
        try std.testing.expectEqual(emitted.position, measured.position);
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        var hashed: wire.Writer = .{ .hasher = &hash };
        try write(Row, value, &hashed);
        try std.testing.expectEqual(emitted.position, hashed.position);
        try std.testing.expectEqual(wire.digest(buffer[0..emitted.position]), hash.finalResult());
        var compared: wire.Writer = .{ .expected = buffer[0..emitted.position] };
        try write(Row, value, &compared);
    }
}

test "legacy sequence hashes preserve long full-width vectors" {
    const Argument = @import("program.zig").Argument;
    inline for (.{ u64, Argument }) |T| {
        var values: [257]T = undefined;
        for (&values, 0..) |*value, index| {
            const id = std.math.maxInt(u64) - index;
            value.* = if (T == u64) id else if (index % 3 == 0) .returned else .{ .slot = id };
        }
        var buffer: [4096]u8 = undefined;
        var emitted: wire.Writer = .{ .output = &buffer };
        try write([]const T, &values, &emitted);
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        var hashed: wire.Writer = .{ .hasher = &hash };
        try write([]const T, &values, &hashed);
        try std.testing.expectEqual(emitted.position, hashed.position);
        try std.testing.expectEqual(wire.digest(buffer[0..emitted.position]), hash.finalResult());
    }
}
