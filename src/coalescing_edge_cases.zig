// Copyright (c) 2026 Boundary contributors. MIT license.
//! Raw admitted stable-slot cases: source lets do not expose simultaneous cycles.
const std = @import("std");
const data = @import("boundary_data");
const source = @import("source.zig");
const ir = data.activation;
pub const Kind = enum { swap, cycle };
const Mutation = enum { none, order, invalid_slot };
const permutations = [_][3]ir.Id{
    .{ 0, 1, 2 }, .{ 0, 2, 1 }, .{ 1, 0, 2 },
    .{ 1, 2, 0 }, .{ 2, 0, 1 }, .{ 2, 1, 0 },
};

pub fn compile(allocator: std.mem.Allocator, kind: Kind, options: data.coalescing.Options) !source.Compiled {
    return build(allocator, if (kind == .swap) &.{ 1, 0 } else &.{ 1, 2, 0 }, &.{ 2, 0, 1 }, .none, options);
}

/// Seeds 0..35 enumerate independent assignment/slot permutations. Adding 64
/// changes only the second body's returned field order, a semantic negative.
/// Adding 128 instead creates a single out-of-range destination for rejection.
pub fn generated(allocator: std.mem.Allocator, seed: usize, options: data.coalescing.Options) !source.Compiled {
    if (seed >= 192 or seed % 64 >= 36) return error.InvalidSeed;
    const ordinal = seed % 64;
    const mutation: Mutation = if (seed >= 128) .invalid_slot else if (seed >= 64) .order else .none;
    return build(allocator, &permutations[ordinal % 6], &permutations[ordinal / 6], mutation, options);
}

fn build(allocator: std.mem.Allocator, order: []const ir.Id, renamed: []const ir.Id, mutation: Mutation, options: data.coalescing.Options) !source.Compiled {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const a = scratch.allocator();
    const functions = try a.alloc(ir.Function, 3);
    const blocks = try a.alloc(ir.Block, 7);
    for (0..2) |id| {
        const inputs: []const ir.Id = if (id == 0) &.{ 0, 1, 2 } else renamed;
        functions[id] = .{ .entry = id * 2, .inputs = inputs, .layout = .{ .slots = &.{ 0, 0, 0, 1 } }, .result = 1 };
        const assignments = try a.alloc(ir.Assignment, order.len);
        for (assignments, order, 0..) |*assignment, from, to| assignment.* = .{
            .destination = inputs[to],
            .source = .{ .slot = inputs[from] },
        };
        blocks[id * 2] = .{ .function = id, .instructions = &.{}, .terminator = .{ .jump = .{ .block = id * 2 + 1, .assignments = assignments } } };
        const operations = try a.alloc(ir.Instruction, 1);
        const operands = try a.dupe(ir.Id, inputs);
        if (id == 1 and mutation == .order) std.mem.swap(ir.Id, &operands[0], &operands[1]);
        operations[0] = .{ .destination = if (id == 1 and mutation == .invalid_slot) 4 else 3, .opcode = .product, .operands = operands };
        blocks[id * 2 + 1] = .{ .function = id, .instructions = operations, .terminator = .{ .return_value = 3 } };
    }
    functions[2] = .{ .entry = 4, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0, 1, 1, 3 } }, .result = 3 };
    for (0..2) |id| {
        const assignments = try a.alloc(ir.Assignment, 1);
        assignments[0] = .{ .destination = 3 + id, .source = .returned };
        blocks[4 + id] = .{ .function = 2, .instructions = &.{}, .terminator = .{ .call = .{
            .function = id,
            .arguments = &.{ 0, 1, 2 },
            .next = .{ .block = 5 + id, .assignments = assignments },
        } } };
    }
    blocks[6] = .{ .function = 2, .instructions = &.{.{ .destination = 5, .opcode = .product, .operands = &.{ 3, 4 } }}, .terminator = .{ .return_value = 5 } };
    const program: ir.Program = .{
        .roots = .{ .entry = 2, .result = 3, .failure = 2 },
        .schemas = &.{ .u64, .{ .product = &.{ 0, 0, 0 } }, .unit, .{ .product = &.{ 1, 1 } } },
        .constants = &.{},
        .effects = &.{},
        .functions = functions,
        .blocks = blocks,
    };
    const result = try data.coalescing.run(allocator, program, options);
    return .{ .arena = result.arena, .program = result.program, .flow = result.flow };
}
