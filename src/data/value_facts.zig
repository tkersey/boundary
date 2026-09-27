// Copyright (c) 2026 Boundary contributors. MIT license.
//! Temporary stable-slot definition facts. Incoming values are unknown; a
//! definition never means a slot keeps that value after a later assignment.
const std = @import("std");
const ir = @import("activation.zig");
const p = @import("program.zig");
const image = @import("program_image.zig");
const ownership = @import("activation_ownership.zig");
pub const Error = ownership.Error || image.Error || error{StaleFacts};
pub const Version = usize;
pub const Value = struct {
    boolean: ?bool = null,
    unsigned: ?u64 = null,
    constructor: ?p.Id = null,
    /// The producing computation instruction, not an opaque environment projection.
    construction: ?usize = null,
    maximum: ?u64 = null,
    known_zero: u64 = 0,
    known_one: u64 = 0,
    length: ?u64 = null,
    length_bound: ?u64 = null,
};
pub const Definition = struct {
    slot: p.Id,
    instruction: ?usize,
    operands: []const Version,
    value: Value,
};
pub const Block = struct {
    reachable: bool,
    definitions: []const Definition,
    /// Version before each instruction's write, and at the terminator.
    results: []const Version,
    exit: []const Version,
};
pub const Facts = struct {
    arena: std.heap.ArenaAllocator,
    epoch: [32]u8,
    blocks: []const Block,
    transfers: usize,
    pub fn deinit(self: *Facts) void {
        self.arena.deinit();
        self.* = undefined;
    }
    pub fn requireEpoch(self: *const Facts, allocator: std.mem.Allocator, program: ir.Program) Error!void {
        if (!std.mem.eql(u8, &self.epoch, &try image.identity(allocator, program))) return error.StaleFacts;
    }
};

/// Admission runs before facts can hide an originally invalid instruction.
/// This first consumer uses block-local definitions. Cross-block incoming facts
/// remain unknown until a checked join/edge transfer supplies them.
pub fn analyze(allocator: std.mem.Allocator, program: ir.Program) Error!Facts {
    var checked = try ownership.analyze(allocator, program);
    defer checked.deinit();
    const epoch = try image.identity(allocator, program);
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();
    const blocks = try a.alloc(Block, program.blocks.len);
    var transfers: usize = 0;
    for (program.blocks, blocks, 0..) |block, *out, block_id| {
        const layout = program.functions[@intCast(block.function)].layout.slots;
        const versions = try a.alloc(Version, layout.len);
        var definitions: std.ArrayList(Definition) = .empty;
        for (layout, versions, 0..) |schema, *version, slot| {
            version.* = definitions.items.len;
            try definitions.append(a, .{ .slot = slot, .instruction = null, .operands = &.{}, .value = bounds(program.schemas[@intCast(schema)]) });
        }
        const results = try a.alloc(Version, block.instructions.len);
        for (block.instructions, results, 0..) |instruction, *result, index| {
            const operands = try a.alloc(Version, instruction.operands.len);
            for (instruction.operands, operands) |slot, *version| version.* = versions[@intCast(slot)];
            const value = transfer(program, layout[@intCast(instruction.destination)], instruction, operands, definitions.items, index);
            result.* = definitions.items.len;
            try definitions.append(a, .{ .slot = instruction.destination, .instruction = index, .operands = operands, .value = value });
            versions[@intCast(instruction.destination)] = result.*;
            transfers += 1;
        }
        out.* = .{ .reachable = checked.entries[block_id] != null, .definitions = try definitions.toOwnedSlice(a), .results = results, .exit = versions };
    }
    return .{ .arena = arena, .epoch = epoch, .blocks = blocks, .transfers = transfers };
}
fn bounds(schema: p.Schema) Value {
    return switch (schema) {
        .u8 => .{ .maximum = 255, .known_zero = ~@as(u64, 255) },
        .u16 => .{ .maximum = 65535, .known_zero = ~@as(u64, 65535) },
        .u32 => .{ .maximum = 4294967295, .known_zero = ~@as(u64, 4294967295) },
        .u64 => .{ .maximum = std.math.maxInt(u64) },
        .array => |v| .{ .length = v.length, .length_bound = v.length },
        .vector => |v| .{ .length_bound = v.maximum },
        else => .{},
    };
}
fn number(value: u64) Value {
    return .{ .unsigned = value, .maximum = value, .known_zero = ~value, .known_one = value };
}
fn transfer(program: ir.Program, schema: p.Id, instruction: ir.Instruction, operands: []const Version, definitions: []const Definition, index: usize) Value {
    const result = bounds(program.schemas[@intCast(schema)]);
    const left: Value = if (operands.len > 0) definitions[operands[0]].value else .{};
    const right: Value = if (operands.len > 1) definitions[operands[1]].value else .{};
    return switch (instruction.opcode) {
        .constant => blk: {
            const literal = program.constants[@intCast(instruction.immediate)];
            break :blk switch (program.schemas[@intCast(literal.schema)]) {
                .boolean => .{ .boolean = literal.bytes[0] == 1 },
                .u8 => number(literal.bytes[0]),
                .u16 => number(std.mem.readInt(u16, literal.bytes[0..2], .little)),
                .u32 => number(std.mem.readInt(u32, literal.bytes[0..4], .little)),
                .u64 => number(std.mem.readInt(u64, literal.bytes[0..8], .little)),
                else => result,
            };
        },
        .move => left,
        .computation => .{ .constructor = instruction.immediate, .construction = index },
        .boolean_not => if (left.boolean) |v| .{ .boolean = !v } else result,
        .equal => if (left.unsigned != null and right.unsigned != null) .{ .boolean = left.unsigned.? == right.unsigned.? } else if (left.boolean != null and right.boolean != null) .{ .boolean = left.boolean.? == right.boolean.? } else result,
        .less => if (left.unsigned != null and right.unsigned != null) .{ .boolean = left.unsigned.? < right.unsigned.? } else result,
        .integer_bit_and => blk: {
            if (result.maximum == null) break :blk result;
            if (left.unsigned != null and right.unsigned != null) break :blk number(left.unsigned.? & right.unsigned.?);
            const mask = right.unsigned orelse left.unsigned orelse break :blk result;
            const other = if (right.unsigned != null) left else right;
            if (mask == 0) break :blk number(0);
            break :blk .{ .maximum = mask & ~other.known_zero, .known_zero = other.known_zero | ~mask, .known_one = other.known_one & mask };
        },
        .sequence => .{ .length = instruction.operands.len, .length_bound = result.length_bound },
        .sequence_length => if (left.length) |length| number(length) else .{ .maximum = left.length_bound },
        .select => if (left.boolean) |condition| definitions[operands[if (condition) 1 else 2]].value else result,
        else => result,
    };
}
