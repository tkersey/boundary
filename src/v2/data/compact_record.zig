// Copyright (c) 2026 Boundary contributors. MIT license.
//! BPC1 record projection. Scalar/tag contracts remain the legacy contracts.
const std = @import("std");
const wire = @import("wire.zig");
const record = @import("record.zig");
const sequence = @import("compact_sequence.zig");
const p = @import("program.zig");
const parameters = @import("compact_parameters.zig");
const Error = record.Error;

comptime {
    // These two abbreviations have explicit grammars rather than reflected fields.
    std.debug.assert(std.meta.fields(p.Instruction).len == 5);
    std.debug.assert(std.meta.fields(p.Literal).len == 2);
    for (std.meta.fields(p.Opcode)) |field| std.debug.assert(field.value < 64);
}

pub fn write(comptime T: type, value: T, writer: *wire.Writer, context: *parameters.Writing) Error!void {
    if (T == p.Instruction) return writeInstruction(value, writer, context);
    if (T == p.Literal) return writeLiteral(value, writer);
    switch (@typeInfo(T)) {
        .pointer => |info| {
            if (comptime sequence.supports(info.child))
                return sequence.write(info.child, value, writer);
            try writer.natural(value.len);
            if (info.child == u8) return writer.put(value);
            for (value) |element| try write(info.child, element, writer, context);
        },
        .@"struct" => |info| inline for (info.fields) |field| {
            if (T == p.Block and comptime std.mem.eql(u8, field.name, "parameters")) {
                try context.parameters(value.parameters, writer);
            } else try write(field.type, @field(value, field.name), writer, context);
        },
        .@"union" => {
            try writer.natural(@intFromEnum(std.meta.activeTag(value)));
            switch (value) {
                inline else => |payload| try write(@TypeOf(payload), payload, writer, context),
            }
        },
        .optional => |info| {
            try writer.byte(@intFromBool(value != null));
            if (value) |present| try write(info.child, present, writer, context);
        },
        .array => |info| {
            if (info.child == u8) return writer.put(&value);
            for (value) |element| try write(info.child, element, writer, context);
        },
        else => try record.write(T, value, writer),
    }
}

/// Literal rows use checked physical counts. Compressed sequences validate their
/// full descriptor before expansion. Type nesting is fixed by Program, not input.
pub fn read(
    comptime T: type,
    reader: *wire.Reader,
    allocator: std.mem.Allocator,
    requested: *usize,
    context: parameters.Reading,
) Error!T {
    if (T == p.Instruction) return readInstruction(reader, allocator, requested, context);
    if (T == p.Literal) return readLiteral(reader, allocator, requested);
    return switch (@typeInfo(T)) {
        .pointer => |info| blk: {
            if (comptime sequence.supports(info.child))
                break :blk try sequence.read(info.child, true, reader, allocator, requested);
            const count = try reader.count();
            if (count > reader.input.len - reader.position) return error.Truncated;
            if (info.child == u8) break :blk try reader.take(count);
            try sequence.account(info.child, count, requested);
            const output = try allocator.alloc(info.child, count);
            for (0..count) |index| {
                const value = try read(info.child, reader, allocator, requested, context);
                output[index] = value;
            }
            break :blk output;
        },
        .@"struct" => |info| blk: {
            var value: T = undefined;
            inline for (info.fields) |field| {
                @field(value, field.name) = if (T == p.Block and
                    comptime std.mem.eql(u8, field.name, "parameters"))
                    try context.parameters(reader, allocator, requested)
                else
                    try read(field.type, reader, allocator, requested, context);
            }
            break :blk value;
        },
        .@"union" => |info| blk: {
            const tag = try reader.natural();
            inline for (info.fields) |field| {
                if (tag == @intFromEnum(@field(info.tag_type.?, field.name)))
                    break :blk @unionInit(T, field.name, try read(field.type, reader, allocator, requested, context));
            }
            break :blk error.InvalidTag;
        },
        .optional => |info| switch (try reader.byte()) {
            0 => null,
            1 => try read(info.child, reader, allocator, requested, context),
            else => error.InvalidTag,
        },
        .array => |info| blk: {
            var value: T = undefined;
            if (info.child == u8) {
                @memcpy(&value, try reader.take(info.len));
                break :blk value;
            }
            for (&value) |*element|
                element.* = try read(info.child, reader, allocator, requested, context);
            break :blk value;
        },
        else => try record.read(T, reader, allocator),
    };
}

/// A payload abbreviation, independent of its logical schema: exactly eight
/// bytes can also be spelled as their little-endian unsigned bit pattern.
fn writeLiteral(value: p.Literal, writer: *wire.Writer) Error!void {
    try writer.natural(value.schema);
    try writer.natural(value.bytes.len);
    if (value.bytes.len == 8) {
        const bits = std.mem.readInt(u64, value.bytes[0..8], .little);
        var measured: wire.Writer = .{};
        try measured.natural(bits);
        const abbreviated = measured.position < 8;
        try writer.byte(@intFromBool(abbreviated));
        if (abbreviated) return writer.natural(bits);
    }
    try writer.put(value.bytes);
}

fn readLiteral(
    reader: *wire.Reader,
    allocator: std.mem.Allocator,
    requested: *usize,
) Error!p.Literal {
    const schema = try reader.natural();
    const length = try reader.count();
    if (length == 8) switch (try reader.byte()) {
        0 => {},
        1 => {
            const bits = try reader.natural();
            try sequence.account(u8, 8, requested);
            const bytes = try allocator.alloc(u8, 8);
            std.mem.writeInt(u64, bytes[0..8], bits, .little);
            return .{ .schema = schema, .bytes = bytes };
        },
        else => return error.InvalidTag,
    };
    return .{ .schema = schema, .bytes = try reader.take(length) };
}

fn writeInstruction(value: p.Instruction, writer: *wire.Writer, context: *parameters.Writing) Error!void {
    const tag = @as(u64, @intFromEnum(value.opcode)) |
        @as(u64, if (value.immediate != 0) 64 else 0) |
        @as(u64, if (value.failures.len != 0) 128 else 0);
    try writer.natural(tag);
    try writer.natural(value.result_type);
    try sequence.write(p.Id, value.operands, writer);
    if (value.immediate != 0) try writer.natural(value.immediate);
    if (value.failures.len != 0) try write([]const p.InstructionFailure, value.failures, writer, context);
}

fn readInstruction(
    reader: *wire.Reader,
    allocator: std.mem.Allocator,
    requested: *usize,
    context: parameters.Reading,
) Error!p.Instruction {
    const tag = try reader.natural();
    if (tag > 255) return error.InvalidTag;
    const opcode = std.enums.fromInt(p.Opcode, tag & 63) orelse return error.InvalidTag;
    return .{
        .opcode = opcode,
        .result_type = try reader.natural(),
        .operands = try sequence.read(p.Id, true, reader, allocator, requested),
        .immediate = if (tag & 64 != 0) try reader.natural() else 0,
        .failures = if (tag & 128 != 0)
            try read([]const p.InstructionFailure, reader, allocator, requested, context)
        else
            &.{},
    };
}
