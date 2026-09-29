// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const p = data.program;
const a = std.testing.allocator;
pub const bounded: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u8, .unit, .boolean },
    .effects = &.{},
    .constants = &.{ .{ .schema = 0, .bytes = &.{50} }, .{ .schema = 0, .bytes = &.{0} }, .{ .schema = 0, .bytes = &.{5} }, .{ .schema = 0, .bytes = &.{3} }, .{ .schema = 0, .bytes = &.{1} }, .{ .schema = 1, .bytes = &.{} } },
    .functions = &.{.{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0, 0, 0, 2, 0, 0, 0, 0, 0 } }, .result = 0 }},
    .blocks = &.{
        .{ .function = 0, .instructions = &.{ .{ .destination = 1, .opcode = .constant, .immediate = 0 }, .{ .destination = 2, .opcode = .constant, .immediate = 1 }, .{ .destination = 3, .opcode = .constant, .immediate = 1 }, .{ .destination = 5, .opcode = .constant, .immediate = 2 }, .{ .destination = 6, .opcode = .constant, .immediate = 3 }, .{ .destination = 9, .opcode = .constant, .immediate = 4 } }, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .less, .operands = &.{ 2, 1 } }}, .terminator = .{ .branch = .{ .condition = 4, .when_true = .{ .block = 2 }, .when_false = .{ .block = 3 } } } },
        .{ .function = 0, .instructions = &.{
            .{ .destination = 7, .opcode = .integer_mul, .operands = &.{ 2, 5 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 5 }} },
            .{ .destination = 8, .opcode = .integer_add, .operands = &.{ 7, 6 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 5 }} },
            .{ .destination = 3, .opcode = .integer_bit_xor, .operands = &.{ 3, 8 } },
            .{ .destination = 2, .opcode = .integer_add, .operands = &.{ 2, 9 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 5 }} },
        }, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
    },
};
pub fn lengthBound(allocator: std.mem.Allocator) !ir.Program {
    var result = bounded;
    result.schemas = &.{ .u64, .unit, .boolean, .{ .vector = .{ .element = 1, .maximum = 50 } } };
    result.constants = &.{ .{ .schema = 0, .bytes = &.{ 50, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 5, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 3, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 1, .bytes = &.{} } };
    const functions = try allocator.dupe(ir.Function, result.functions);
    functions[0].layout.slots = &.{ 3, 0, 0, 0, 2, 0, 0, 0, 0, 0 };
    result.functions = functions;
    const blocks = try allocator.dupe(ir.Block, result.blocks);
    const entry = try allocator.dupe(ir.Instruction, blocks[0].instructions);
    entry[0] = .{ .destination = 1, .opcode = .sequence_length, .operands = &.{0} };
    blocks[0].instructions = entry;
    result.blocks = blocks;
    return result;
}

const Work = struct { multiplications: usize = 0, additions: usize = 0, comparisons: usize = 0, steps: usize = 0 };
fn execute(program: ir.Program, input: []const u8, expected: []const u8) !Work {
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
    defer a.free(bytes);
    _ = try data.program_image.encode(a, program, bytes);
    var session = try world.Session.initImage(a, bytes, input);
    defer session.deinit();
    var work: Work = .{};
    while (true) {
        try std.testing.expect(work.steps < 100000);
        if (session.roots.current) |current| {
            const node = try session.store.get(current);
            if (node == .control) {
                const frame = try session.frames.get(current.id);
                const block = program.blocks[@intCast(node.control.block)];
                if (frame.position < block.instructions.len) switch (block.instructions[frame.position].opcode) {
                    .integer_mul => work.multiplications += 1,
                    .integer_add => work.additions += 1,
                    .less => work.comparisons += 1,
                    else => {},
                };
            }
        }
        const result = try session.run(1);
        work.steps += 1;
        switch (result) {
            .progressed => {
                if (work.steps % 17 == 0) {
                    const checkpoint = try session.checkpoint(a);
                    defer a.free(checkpoint);
                    const restored = try world.Session.restoreImage(a, bytes, checkpoint);
                    session.deinit();
                    session = restored;
                }
            },
            .completed => |value| {
                try std.testing.expectEqualSlices(u8, expected, try session.bytes(&value));
                return work;
            },
            else => return error.UnexpectedOutcome,
        }
    }
}
test "affine recurrence preserves actual lengths and removes dynamic multiplication" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try lengthBound(arena.allocator());
    var checked = try data.affine_induction.run(a, original, null, .{});
    defer checked.deinit();
    var stats: data.closed_compilation.Statistics = .{};
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic, .statistics = &stats });
    defer shared.deinit();
    var linked = try linkOriginal(original);
    defer linked.deinit();
    std.debug.print("affine selection: {any}\n", .{stats});
    for ([_]u8{ 0, 1, 7, 50 }) |n| {
        var expected: u64 = 0;
        for (0..n) |i| expected ^= 3 + 5 * @as(u64, @intCast(i));
        var word: [8]u8 = undefined;
        std.mem.writeInt(u64, &word, expected, .little);
        const before = try execute(original, &.{n}, &word);
        try std.testing.expectEqual(@as(usize, n), before.multiplications);
        for ([_]ir.Program{ checked.program, shared.program, linked.program }, 0..) |program, arm| {
            const after = try execute(program, &.{n}, &word);
            try std.testing.expectEqual(@as(usize, 0), after.multiplications);
            std.debug.print("length={d} arm={d} before={any} after={any}\n", .{ n, arm, before, after });
        }
    }
}
test "valid last useful u8 product does not license an overflowing final recurrence update" {
    var original = bounded;
    var constants = bounded.constants[0..6].*;
    constants[0].bytes = &.{51};
    original.constants = &constants;
    var stats: data.affine_induction.Statistics = .{};
    var checked = try data.affine_induction.run(a, original, &stats, .{});
    defer checked.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.recurrences);
    var expected: u8 = 0;
    for (0..51) |i| expected ^= @intCast(3 + 5 * i);
    _ = try execute(original, &.{0}, &.{expected});
    _ = try execute(checked.program, &.{0}, &.{expected});
}

const base: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .boolean },
    .constants = &.{ .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 1, .bytes = &.{} } },
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 0, 2, 0, 0 } }, .result = 0 }},
    .blocks = &.{
        .{ .function = 0, .instructions = &.{ .{ .destination = 3, .opcode = .constant, .immediate = 0 }, .{ .destination = 4, .opcode = .constant, .immediate = 0 }, .{ .destination = 7, .opcode = .constant, .immediate = 1 } }, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 5, .opcode = .less, .operands = &.{ 3, 0 } }}, .terminator = .{ .branch = .{ .condition = 5, .when_true = .{ .block = 2 }, .when_false = .{ .block = 3 } } } },
        .{ .function = 0, .instructions = &.{
            .{ .destination = 6, .opcode = .integer_bit_xor, .operands = &.{ 1, 2 } },
            .{ .destination = 4, .opcode = .integer_bit_xor, .operands = &.{ 4, 6 } },
            .{ .destination = 3, .opcode = .integer_add, .operands = &.{ 3, 7 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 2 }} },
        }, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
    },
};
pub const guarded: ir.Program = .{
    .roots = base.roots,
    .schemas = base.schemas,
    .constants = base.constants,
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 0, 2, 0, 0, 2, 1 } }, .result = 0 }},
    .blocks = &.{
        base.blocks[0],
        .{ .function = 0, .instructions = base.blocks[1].instructions, .terminator = .{ .branch = .{ .condition = 5, .when_true = .{ .block = 2 }, .when_false = .{ .block = 4 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 8, .opcode = .less, .operands = &.{ 3, 0 } }}, .terminator = .{ .branch = .{ .condition = 8, .when_true = .{ .block = 3 }, .when_false = .{ .block = 5 } } } },
        base.blocks[2],
        base.blocks[3],
        .{ .function = 0, .instructions = &.{.{ .destination = 9, .opcode = .constant, .immediate = 2 }}, .terminator = .{ .fail = 9 } },
    },
};

test "an explicit repeated bound disappears through shared compilation at zero and maximum count" {
    var original = guarded;
    var schemas = guarded.schemas[0..3].*;
    schemas[0] = .u8;
    original.schemas = &schemas;
    original.constants = &.{ .{ .schema = 0, .bytes = &.{0} }, .{ .schema = 0, .bytes = &.{1} }, guarded.constants[2] };
    var checked = try data.induction_reduction.run(a, original, null, .{});
    defer checked.deinit();
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer shared.deinit();
    var linked = try linkOriginal(original);
    defer linked.deinit();
    for ([_]u8{ 0, 1, 7, 255 }) |n| {
        const expected: u8 = if (n % 2 == 0) 0 else 6;
        const before = try execute(original, &.{ n, 5, 3 }, &.{expected});
        try std.testing.expectEqual(@as(usize, n) * 2 + 1, before.comparisons);
        for ([_]ir.Program{ checked.program, shared.program, linked.program }) |program| {
            const after = try execute(program, &.{ n, 5, 3 }, &.{expected});
            try std.testing.expectEqual(@as(usize, n) + 1, after.comparisons);
        }
    }
}
test "signed arithmetic retains its overflow and its original failure payload" {
    var original = bounded;
    var schemas = bounded.schemas[0..3].*;
    schemas[0] = .i8;
    original.schemas = &schemas;
    var stats: data.affine_induction.Statistics = .{};
    var checked = try data.affine_induction.run(a, original, &stats, .{});
    defer checked.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.recurrences);
    for ([_]ir.Program{ original, checked.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var session = try world.Session.initImage(a, bytes, &.{0});
        defer session.deinit();
        const result = try session.run(null);
        try std.testing.expect(result == .failed);
        try std.testing.expectEqualSlices(u8, &.{}, try session.bytes(&result.failed));
    }
}

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

pub fn sequenceGuard(allocator: std.mem.Allocator, use_capacity: bool) !ir.Program {
    var program = guarded;
    program.roots.failure = 0;
    program.schemas = &.{ .u64, .unit, .boolean, .{ .vector = .{ .element = 1, .maximum = 50 } }, .{ .sum = &.{ 1, 1 } } };
    program.constants = &.{ guarded.constants[0], guarded.constants[1], .{ .schema = 0, .bytes = &.{ 99, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 73, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 50, 0, 0, 0, 0, 0, 0, 0 } } };
    const functions = try allocator.dupe(ir.Function, program.functions);
    functions[0].layout.slots = &.{ 3, 0, 0, 0, 0, 2, 0, 0, 2, 0, 0, 4, 0, 1 };
    program.functions = functions;
    const blocks = try allocator.dupe(ir.Block, program.blocks);
    const init = try allocator.alloc(ir.Instruction, blocks[0].instructions.len + 2);
    @memcpy(init[0..blocks[0].instructions.len], blocks[0].instructions);
    init[init.len - 2] = .{ .destination = 10, .opcode = .sequence_length, .operands = &.{0} };
    init[init.len - 1] = .{ .destination = 12, .opcode = .constant, .immediate = 4 };
    blocks[0].instructions = init;
    blocks[1].instructions = try allocator.dupe(ir.Instruction, &.{.{ .destination = 5, .opcode = .less, .operands = try allocator.dupe(p.Id, &.{ 3, if (use_capacity) @as(p.Id, 12) else 10 }) }});
    blocks[2].instructions = &.{.{ .destination = 8, .opcode = .less, .operands = &.{ 3, 10 } }};
    const work = try allocator.alloc(ir.Instruction, blocks[3].instructions.len + 2);
    work[0] = .{ .destination = 11, .opcode = .sequence_get, .operands = &.{ 0, 3 } };
    work[1] = .{ .destination = 13, .opcode = .variant_payload, .operands = &.{11}, .immediate = 1, .failures = &.{.{ .kind = .invalid_variant, .value = 3 }} };
    @memcpy(work[2..], blocks[3].instructions);
    blocks[3].instructions = work;
    program.blocks = blocks;
    return program;
}

test "short vectors use actual length and retain the original capacity-mismatch fault" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try sequenceGuard(arena.allocator(), false);
    var checked = try data.induction_reduction.run(a, original, null, .{});
    defer checked.deinit();
    var linked = try linkOriginal(original);
    defer linked.deinit();
    for ([_]u8{ 0, 1, 7, 50 }) |n| {
        var input: [17]u8 = @splat(0);
        input[0] = n;
        input[1] = 5;
        input[9] = 3;
        var expected: [8]u8 = @splat(0);
        if (n % 2 == 1) expected[0] = 6;
        for ([_]ir.Program{ original, checked.program, linked.program }) |program| {
            _ = try execute(program, &input, &expected);
        }
    }
    const wrong = try sequenceGuard(arena.allocator(), true);
    var stats: data.induction_reduction.Statistics = .{};
    var retained = try data.induction_reduction.run(a, wrong, &stats, .{});
    defer retained.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.guards_removed);
    for ([_]ir.Program{ wrong, retained.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var input: [17]u8 = @splat(0);
        input[0] = 3;
        input[1] = 5;
        input[9] = 3;
        var session = try world.Session.initImage(a, bytes, &input);
        defer session.deinit();
        const result = try session.run(null);
        try std.testing.expect(result == .failed);
        try std.testing.expectEqualSlices(u8, &.{ 99, 0, 0, 0, 0, 0, 0, 0 }, try session.bytes(&result.failed));
    }
}
