// Copyright (c) 2026 Boundary contributors. MIT license.
//! Exact first-order value translation from an admitted BPI1 schema table.
//! This converts data encodings only; it never evaluates an application.
const std = @import("std");
const data = @import("boundary_data_v2");
const legacy = @import("value.zig");
const p = data.program;

pub const Schemas = struct {
    arena: std.heap.ArenaAllocator,
    /// Every original schema retains its index. A missing unit schema is appended.
    types: []const p.Schema,

    pub fn deinit(self: *Schemas) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

fn integer(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}

/// The table must come from the pure BPI1 decoder. Bounds and explicit enum
/// tags remain type data, including uninhabited legacy failure domains.
pub fn schemas(allocator: std.mem.Allocator, table: legacy.Table) !Schemas {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const storage = arena.allocator();
    var unit: p.Id = table.count();
    for (0..table.count()) |id| if ((try table.node(@intCast(id))).kind == .unit) {
        unit = id;
        break;
    };
    const result = try storage.alloc(p.Schema, @as(usize, table.count()) + @intFromBool(unit == table.count()));
    if (unit == table.count()) result[@intCast(unit)] = .unit;
    for (result[0..table.count()], 0..) |*target, id| {
        const node = try table.node(@intCast(id));
        target.* = switch (node.kind) {
            .unit => .unit,
            .bool => .boolean,
            .i8 => .i8,
            .i16 => .i16,
            .i32 => .i32,
            .i64 => .i64,
            .u8 => .u8,
            .u16 => .u16,
            .u32 => .u32,
            .u64 => .u64,
            .bytes => .{ .bounded_bytes = integer(node.payload, 0) },
            .text => .{ .bounded_text = integer(node.payload, 0) },
            .array => .{ .array = .{ .element = integer(node.payload, 4), .length = integer(node.payload, 0) } },
            .vector => .{ .vector = .{ .element = integer(node.payload, 4), .maximum = integer(node.payload, 0) } },
            .optional => .{ .sum = try storage.dupe(p.Id, &.{ unit, integer(node.payload, 0) }) },
            .@"enum" => blk: {
                const tags = try storage.alloc(u32, integer(node.payload, 0));
                for (tags, 0..) |*tag, index| tag.* = integer(node.payload, 4 + index * 4);
                std.mem.sortUnstable(u32, tags, {}, std.sort.asc(u32));
                break :blk .{ .enumeration = tags };
            },
            .product => blk: {
                const fields = try storage.alloc(p.Id, integer(node.payload, 0));
                for (fields, 0..) |*field, index| field.* = integer(node.payload, 4 + index * 4);
                break :blk .{ .product = fields };
            },
            .sum => blk: {
                const count = integer(node.payload, 4);
                if (count == 0) break :blk .{ .enumeration = &.{} };
                const variants = try storage.alloc(p.Id, count);
                for (variants, 0..) |*variant, index| variant.* = integer(node.payload, 12 + index * 8);
                break :blk .{ .sum = variants };
            },
        };
    }
    const facts = try data.admission.schemas(storage, result);
    _ = facts;
    return .{ .arena = arena, .types = result };
}

const Direction = enum { to_v2, to_v1 };

fn readU32(reader: *data.wire.Reader) !u32 {
    return integer(try reader.take(4), 0);
}

fn writeU32(writer: *data.wire.Writer, value: u64) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, std.math.cast(u32, value) orelse return error.InvalidValue, .little);
    try writer.put(&bytes);
}

fn convert(
    allocator: std.mem.Allocator,
    table: legacy.Table,
    schema: u32,
    input: []const u8,
    direction: Direction,
    writer: *data.wire.Writer,
) !void {
    const Task = struct { schema: u32, count: u64 };
    var tasks: std.ArrayList(Task) = .empty;
    defer tasks.deinit(allocator);
    var reader: data.wire.Reader = .{ .input = input };
    try tasks.append(allocator, .{ .schema = schema, .count = 1 });
    while (tasks.pop()) |task| {
        const node = try table.node(task.schema);
        if (task.count == 0 or node.maximum_encoded_size == 0) continue;
        if (task.count > 1) try tasks.append(allocator, .{ .schema = task.schema, .count = task.count - 1 });
        switch (node.kind) {
            .unit => {},
            .bool, .i8, .u8 => try writer.put(try reader.take(1)),
            .i16, .u16 => try writer.put(try reader.take(2)),
            .i32, .u32, .@"enum" => try writer.put(try reader.take(4)),
            .i64, .u64 => try writer.put(try reader.take(8)),
            .bytes, .text => {
                const count = if (direction == .to_v2) try readU32(&reader) else try reader.natural();
                const bytes = try reader.take(std.math.cast(usize, count) orelse return error.InvalidValue);
                if (direction == .to_v2) try writer.bytes(bytes) else {
                    try writeU32(writer, count);
                    try writer.put(bytes);
                }
            },
            .array => try tasks.append(allocator, .{ .schema = integer(node.payload, 4), .count = integer(node.payload, 0) }),
            .vector => {
                const count = if (direction == .to_v2) try readU32(&reader) else try reader.natural();
                if (direction == .to_v2) try writer.natural(count) else try writeU32(writer, count);
                try tasks.append(allocator, .{ .schema = integer(node.payload, 4), .count = count });
            },
            .optional => {
                const present = if (direction == .to_v2) try reader.byte() else try reader.natural();
                if (present > 1) return error.InvalidValue;
                if (direction == .to_v2) try writer.natural(present) else try writer.put(&.{@intCast(present)});
                if (present == 1) try tasks.append(allocator, .{ .schema = integer(node.payload, 0), .count = 1 });
            },
            .product => {
                var index: usize = integer(node.payload, 0);
                while (index != 0) {
                    index -= 1;
                    try tasks.append(allocator, .{ .schema = integer(node.payload, 4 + index * 4), .count = 1 });
                }
            },
            .sum => {
                const count = integer(node.payload, 4);
                var index: u64 = 0;
                if (direction == .to_v2) {
                    const tag = try readU32(&reader);
                    while (index < count and integer(node.payload, 8 + @as(usize, @intCast(index)) * 8) != tag) : (index += 1) {}
                    if (index == count) return error.InvalidValue;
                    try writer.natural(index);
                } else {
                    index = try reader.natural();
                    if (index >= count) return error.InvalidValue;
                    try writeU32(writer, integer(node.payload, 8 + @as(usize, @intCast(index)) * 8));
                }
                try tasks.append(allocator, .{ .schema = integer(node.payload, 12 + @as(usize, @intCast(index)) * 8), .count = 1 });
            },
        }
    }
    try reader.finish();
}

fn validateV1(allocator: std.mem.Allocator, table: legacy.Table, schema: u32, bytes: []const u8) !void {
    const tasks = try allocator.alloc(legacy.ValueTask, 2048);
    defer allocator.free(tasks);
    try legacy.validateValue(table, schema, bytes, tasks);
}

fn transcode(allocator: std.mem.Allocator, table: legacy.Table, schema: u32, bytes: []const u8, direction: Direction) ![]u8 {
    if (direction == .to_v2) try validateV1(allocator, table, schema, bytes) else {
        var translated = try schemas(allocator, table);
        defer translated.deinit();
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();
        const facts = try data.admission.schemas(scratch.allocator(), translated.types);
        try data.admission.value(scratch.allocator(), translated.types, facts, .{ .schema = schema, .bytes = bytes });
    }
    var measure: data.wire.Writer = .{};
    try convert(allocator, table, schema, bytes, direction, &measure);
    const output = try allocator.alloc(u8, measure.position);
    errdefer allocator.free(output);
    var writer: data.wire.Writer = .{ .output = output };
    try convert(allocator, table, schema, bytes, direction, &writer);
    return output;
}

pub fn toV2(allocator: std.mem.Allocator, table: legacy.Table, schema: u32, bytes: []const u8) ![]u8 {
    return transcode(allocator, table, schema, bytes, .to_v2);
}

pub fn toV1(allocator: std.mem.Allocator, table: legacy.Table, schema: u32, bytes: []const u8) ![]u8 {
    return transcode(allocator, table, schema, bytes, .to_v1);
}
