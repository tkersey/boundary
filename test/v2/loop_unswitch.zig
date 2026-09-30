// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const boundary = @import("boundary");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const p = data.program;
const a = std.testing.allocator;
pub const selectable: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .boolean },
    .constants = &.{ .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 1, .bytes = &.{} } },
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 2, 0, 0, 0, 2, 0 } }, .result = 0 }},
    .blocks = &.{
        .{ .function = 0, .instructions = &.{ .{ .destination = 3, .opcode = .constant, .immediate = 0 }, .{ .destination = 4, .opcode = .constant, .immediate = 0 }, .{ .destination = 6, .opcode = .constant, .immediate = 1 } }, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 5, .opcode = .less, .operands = &.{ 3, 0 } }}, .terminator = .{ .branch = .{ .condition = 5, .when_true = .{ .block = 2 }, .when_false = .{ .block = 6 } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 1, .when_true = .{ .block = 3 }, .when_false = .{ .block = 4 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .integer_bit_xor, .operands = &.{ 4, 2 } }}, .terminator = .{ .jump = .{ .block = 5 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .integer_bit_or, .operands = &.{ 4, 2 } }}, .terminator = .{ .jump = .{ .block = 5 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .integer_add, .operands = &.{ 3, 6 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 2 }} }}, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
    },
};
fn linkOriginal(original: ir.Program) !data.linker.Linked {
    const borrows = try a.alloc(data.borrow_contract.Summary, original.functions.len);
    defer a.free(borrows);
    for (borrows, 0..) |*summary, id| summary.* = .{ .function = id };
    const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = original.roots.entry } }}, .borrows = borrows };
    const bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(bytes);
    _ = try data.component.encode(a, object, bytes);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "context", .object = bytes }}, &.{}, .{ .instance = "context", .symbol = "main" }, .{ .contract = .semantic });
    errdefer linked.deinit();
    @memset(bytes, 0xff);
    return linked;
}

const Observation = struct { steps: usize = 0, tests: usize = 0, guards: usize = 0, products: usize = 0, cell_creations: usize = 0, cell_reads: usize = 0, cell_writes: usize = 0, checkpoint_bytes: usize = 0 };
fn execute(program: ir.Program, n: u64, flag: bool, value: u64, expected: u64) !Observation {
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
    defer a.free(bytes);
    _ = try data.program_image.encode(a, program, bytes);
    var input: [17]u8 = undefined;
    std.mem.writeInt(u64, input[0..8], n, .little);
    input[8] = @intFromBool(flag);
    std.mem.writeInt(u64, input[9..17], value, .little);
    var session = try world.Session.initImage(a, bytes, &input);
    defer session.deinit();
    var observed: Observation = .{};
    var restored = false;
    while (true) {
        try std.testing.expect(observed.steps < 1_000_000);
        if (session.roots.current) |current| {
            const node = try session.store.get(current);
            if (node == .control) {
                const frame = try session.frames.get(current.id);
                const block = program.blocks[@intCast(node.control.block)];
                if (frame.position < block.instructions.len) {
                    const op = block.instructions[frame.position];
                    observed.guards += @intFromBool(op.opcode == .less);
                    observed.products += @intFromBool(op.opcode == .product);
                    observed.cell_creations += @intFromBool(op.opcode == .cell_new);
                    observed.cell_reads += @intFromBool(op.opcode == .cell_get);
                    observed.cell_writes += @intFromBool(op.opcode == .cell_set);
                } else if (block.terminator == .branch) {
                    var local = false;
                    for (block.instructions) |op| if (op.destination == block.terminator.branch.condition) {
                        local = true;
                    };
                    observed.tests += @intFromBool(!local);
                }
            }
        }
        if (!restored and observed.tests == 1) {
            const checkpoint = try session.checkpoint(a);
            defer a.free(checkpoint);
            observed.checkpoint_bytes = checkpoint.len;
            const next = try world.Session.restoreImage(a, bytes, checkpoint);
            session.deinit();
            session = next;
            restored = true;
        }
        const out = try session.run(1);
        observed.steps += 1;
        switch (out) {
            .progressed => {},
            .completed => |result| {
                var word: [8]u8 = undefined;
                std.mem.writeInt(u64, &word, expected, .little);
                try std.testing.expectEqualSlices(u8, &word, try session.bytes(&result));
                return observed;
            },
            else => return error.UnexpectedOutcome,
        }
    }
}
test "unknown runtime Boolean dispatch executes once and both specialized loops preserve their results" {
    var checked = try data.loop_unswitch.run(a, selectable, null, .{});
    defer checked.deinit();
    var stats: data.closed_compilation.Statistics = .{};
    var shared = try data.closed_compilation.run(a, selectable, .{ .contract = .semantic, .statistics = &stats });
    defer shared.deinit();
    var linked = try linkOriginal(selectable);
    defer linked.deinit();
    std.debug.print("unswitch selection: {any}\n", .{stats});
    for ([_]u64{ 0, 1, 2, 16, 257 }) |n| for ([_]bool{ false, true }) |flag| {
        const expected: u64 = if (n == 0 or (flag and n % 2 == 0)) 0 else 73;
        const before = try execute(selectable, n, flag, 73, expected);
        try std.testing.expectEqual(n, before.tests);
        for ([_]ir.Program{ checked.program, shared.program, linked.program }, 0..) |program, arm| {
            const after = try execute(program, n, flag, 73, expected);
            try std.testing.expectEqual(@as(usize, if (n == 0) 0 else 1), after.tests);
            try std.testing.expectEqual(before.guards, after.guards);
            std.debug.print("n={d} flag={any} arm={d} before={any} after={any}\n", .{ n, flag, arm, before, after });
        }
    };
}
test "structural compilation preserves repeated conditional tests" {
    var structural = try data.closed_compilation.run(a, selectable, .{ .contract = .structural });
    defer structural.deinit();
    const result = try execute(structural.program, 16, true, 73, 0);
    try std.testing.expectEqual(@as(usize, 16), result.tests);
}

pub const cells: ir.Program = .{
    .roots = selectable.roots,
    .schemas = &.{ .u64, .unit, .boolean, .{ .internal = .{ .region = 0 } }, .{ .internal = .{ .cell = .{ .element = 0, .region = 0 } } }, .{ .internal = .{ .computation = .{ .parameters = &.{ 3, 0, 2, 0 }, .result = 0, .use = .reusable, .regions = &.{0} } } } },
    .constants = selectable.constants,
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 2, 0, 5, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 3, 0, 2, 0, 0, 0, 2, 0, 4, 0, 1 } }, .result = 0, .regions = &.{0} },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .computation, .immediate = 0 }}, .terminator = .{ .with_region = .{ .region = 0, .body = 3, .arguments = &.{ 0, 1, 2 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
        .{ .function = 1, .instructions = &.{ .{ .destination = 4, .opcode = .constant, .immediate = 0 }, .{ .destination = 5, .opcode = .constant, .immediate = 0 }, .{ .destination = 7, .opcode = .constant, .immediate = 1 } }, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 6, .opcode = .less, .operands = &.{ 4, 1 } }}, .terminator = .{ .branch = .{ .condition = 6, .when_true = .{ .block = 4 }, .when_false = .{ .block = 8 } } } },
        .{ .function = 1, .instructions = &.{ .{ .destination = 8, .opcode = .cell_new, .operands = &.{ 0, 3 } }, .{ .destination = 9, .opcode = .cell_get, .operands = &.{8} } }, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 5 }, .when_false = .{ .block = 6 } } } },
        .{ .function = 1, .instructions = &.{ .{ .destination = 10, .opcode = .cell_set, .operands = &.{ 8, 4 } }, .{ .destination = 9, .opcode = .cell_get, .operands = &.{8} }, .{ .destination = 5, .opcode = .integer_bit_xor, .operands = &.{ 5, 9 } } }, .terminator = .{ .jump = .{ .block = 7 } } },
        .{ .function = 1, .instructions = &.{ .{ .destination = 10, .opcode = .cell_set, .operands = &.{ 8, 3 } }, .{ .destination = 9, .opcode = .cell_get, .operands = &.{8} }, .{ .destination = 5, .opcode = .integer_bit_or, .operands = &.{ 5, 9 } } }, .terminator = .{ .jump = .{ .block = 7 } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 4, .opcode = .integer_add, .operands = &.{ 4, 7 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 2 }} }}, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 5 } },
    },
    .scopes = .{ .region_count = 1, .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 5 }},
};

test "specialized region loops retain every cell allocation and mutation in order" {
    var stats: data.loop_unswitch.Statistics = .{};
    var checked = try data.loop_unswitch.run(a, cells, &stats, .{});
    defer checked.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.unswitched);
    var shared = try data.closed_compilation.run(a, cells, .{ .contract = .semantic });
    defer shared.deinit();
    var linked = try linkOriginal(cells);
    defer linked.deinit();
    for ([_]u64{ 0, 1, 3, 16 }) |n| for ([_]bool{ false, true }) |flag| {
        var expected: u64 = 0;
        if (flag) {
            for (0..@intCast(n)) |i| expected ^= @intCast(i);
        } else if (n != 0) expected = 73;
        for ([_]ir.Program{ cells, checked.program, shared.program, linked.program }, 0..) |program, arm| {
            const observed = try execute(program, n, flag, 73, expected);
            try std.testing.expectEqual(n, observed.cell_creations);
            if (arm < 2) try std.testing.expectEqual(n * 2, observed.cell_reads);
            try std.testing.expectEqual(n, observed.cell_writes);
            try std.testing.expectEqual(if (arm == 1) @as(u64, if (n == 0) 0 else 1) else n, observed.tests);
        }
    };
}
test "failing dispatch prefix keeps its original zero-trip boundary" {
    var original = selectable;
    var functions = selectable.functions[0..1].*;
    functions[0].layout.slots = &.{ 0, 2, 0, 0, 0, 2, 0, 0 };
    original.functions = &functions;
    var blocks = selectable.blocks[0..7].*;
    blocks[2].instructions = &.{.{ .destination = 7, .opcode = .integer_div, .operands = &.{ 2, 3 }, .failures = &.{ .{ .kind = .arithmetic_overflow, .value = 2 }, .{ .kind = .division_by_zero, .value = 2 } } }};
    original.blocks = &blocks;
    var checked = try data.loop_unswitch.run(a, original, null, .{});
    defer checked.deinit();
    for ([_]bool{ false, true }) |flag| {
        _ = try execute(original, 0, flag, 73, 0);
        _ = try execute(checked.program, 0, flag, 73, 0);
        for ([_]ir.Program{ original, checked.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var args: [17]u8 = @splat(0);
            args[0] = 1;
            args[8] = @intFromBool(flag);
            args[9] = 73;
            var session = try world.Session.initImage(a, bytes, &args);
            defer session.deinit();
            const outcome = try session.run(null);
            try std.testing.expect(outcome == .failed);
            try std.testing.expectEqualSlices(u8, &.{}, try session.bytes(&outcome.failed));
        }
    }
}

pub fn branchCells(allocator: std.mem.Allocator) !ir.Program {
    var program = cells;
    const blocks = try allocator.dupe(ir.Block, cells.blocks);
    const prefix = cells.blocks[4].instructions;
    blocks[4].instructions = &.{};
    for ([_]usize{ 5, 6 }) |id| {
        const original = cells.blocks[id].instructions;
        const instructions = try allocator.alloc(ir.Instruction, prefix.len + original.len);
        @memcpy(instructions[0..prefix.len], prefix);
        @memcpy(instructions[prefix.len..], original);
        blocks[id].instructions = instructions;
    }
    program.blocks = blocks;
    return program;
}

test "canonical unswitching preserves branch-local allocation instances on both paths" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try branchCells(arena.allocator());
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer shared.deinit();
    var linked = try linkOriginal(original);
    defer linked.deinit();
    for ([_]u64{ 0, 1, 3, 16 }) |n| for ([_]bool{ false, true }) |flag| {
        var expected: u64 = 0;
        if (flag) {
            for (0..@intCast(n)) |i| expected ^= @intCast(i);
        } else if (n != 0) expected = 73;
        for ([_]ir.Program{ original, shared.program, linked.program }, 0..) |program, arm| {
            const observed = try execute(program, n, flag, 73, expected);
            try std.testing.expectEqual(n, observed.cell_creations);
            try std.testing.expectEqual(n, observed.cell_writes);
            try std.testing.expectEqual(if (arm == 0) n else @as(u64, if (n == 0) 0 else 1), observed.tests);
        }
    };
}
