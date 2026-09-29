// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const data = @import("boundary_data");
const boundary = @import("boundary");
const world = @import("world");
const ir = data.activation;
const p = data.program;
const a = std.testing.allocator;
pub const counted: ir.Program = .{
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

const Observation = struct { steps: usize = 0, xor_evaluations: usize = 0, guards: usize = 0, checkpoint_bytes: usize = 0 };
fn execute(program: ir.Program, arguments: []const u64, expected: u64) !Observation {
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
    defer a.free(bytes);
    _ = try data.program_image.encode(a, program, bytes);
    const input = try a.alloc(u8, arguments.len * 8);
    defer a.free(input);
    for (arguments, 0..) |value, i| std.mem.writeInt(u64, input[i * 8 ..][0..8], value, .little);
    var session = try world.Session.initImage(a, bytes, input);
    defer session.deinit();
    var observation: Observation = .{};
    var restored = false;
    while (true) {
        try std.testing.expect(observation.steps < 1_000_000);
        if (session.roots.current) |current| {
            const node = try session.store.get(current);
            if (node == .control) {
                const frame = try session.frames.get(current.id);
                const block = program.blocks[@intCast(node.control.block)];
                if (frame.position < block.instructions.len) {
                    const op = block.instructions[frame.position];
                    observation.xor_evaluations += @intFromBool(op.opcode == .integer_bit_xor);
                    observation.guards += @intFromBool(op.opcode == .less);
                }
            }
        }
        if (!restored and observation.xor_evaluations == 1) {
            const checkpoint = try session.checkpoint(a);
            defer a.free(checkpoint);
            observation.checkpoint_bytes = checkpoint.len;
            const replacement = try world.Session.restoreImage(a, bytes, checkpoint);
            session.deinit();
            session = replacement;
            restored = true;
        }
        const outcome = try session.run(1);
        observation.steps += 1;
        switch (outcome) {
            .progressed => {},
            .completed => |value| {
                var result: [8]u8 = undefined;
                std.mem.writeInt(u64, &result, expected, .little);
                try std.testing.expectEqualSlices(u8, &result, try session.bytes(&value));
                return observation;
            },
            else => return error.UnexpectedOutcome,
        }
    }
}
test "invariant scalar executes once with proven placement through shared compilation and source-free linking" {
    var checked = try data.loop_motion.run(a, counted, null, .{});
    defer checked.deinit();
    var stats: data.closed_compilation.Statistics = .{};
    var shared = try data.closed_compilation.run(a, counted, .{ .contract = .semantic, .statistics = &stats });
    defer shared.deinit();
    var linked = try linkOriginal(counted);
    defer linked.deinit();
    std.debug.print("loop selection: {any}\n", .{stats});
    for ([_]u64{ 0, 1, 16, 257 }) |n| {
        const expected = if (n % 2 == 0) 0 else @as(u64, 0x1234 ^ 0xabc);
        const before = try execute(counted, &.{ n, 0x1234, 0xabc }, expected);
        try std.testing.expectEqual(2 * n, before.xor_evaluations);
        for ([_]ir.Program{ checked.program, shared.program, linked.program }, 0..) |program, arm| {
            const after = try execute(program, &.{ n, 0x1234, 0xabc }, expected);
            try std.testing.expectEqual(n + 1, after.xor_evaluations);
            try std.testing.expectEqual(n + 1, after.guards);
            std.debug.print("n={d} arm={d} before={any} after={any}\n", .{ n, arm, before, after });
        }
    }
}

pub const nested: ir.Program = .{
    .roots = counted.roots,
    .schemas = counted.schemas,
    .constants = counted.constants,
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 0, 0, 2, 0, 0 } }, .result = 0 }},
    .blocks = &.{
        .{ .function = 0, .instructions = &.{ .{ .destination = 3, .opcode = .constant, .immediate = 0 }, .{ .destination = 5, .opcode = .constant, .immediate = 0 }, .{ .destination = 8, .opcode = .constant, .immediate = 1 } }, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 6, .opcode = .less, .operands = &.{ 3, 0 } }}, .terminator = .{ .branch = .{ .condition = 6, .when_true = .{ .block = 2 }, .when_false = .{ .block = 6 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 6, .opcode = .less, .operands = &.{ 4, 1 } }}, .terminator = .{ .branch = .{ .condition = 6, .when_true = .{ .block = 4 }, .when_false = .{ .block = 5 } } } },
        .{ .function = 0, .instructions = &.{
            .{ .destination = 7, .opcode = .integer_bit_xor, .operands = &.{ 3, 2 } },
            .{ .destination = 5, .opcode = .integer_bit_xor, .operands = &.{ 5, 7 } },
            .{ .destination = 4, .opcode = .integer_add, .operands = &.{ 4, 8 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 2 }} },
        }, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .integer_add, .operands = &.{ 3, 8 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 2 }} }}, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 5 } },
    },
};

pub const mutable: ir.Program = .{
    .roots = counted.roots,
    .schemas = &.{ .u64, .unit, .boolean, .{ .internal = .{ .region = 0 } }, .{ .internal = .{ .cell = .{ .element = 0, .region = 0 } } }, .{ .internal = .{ .computation = .{ .parameters = &.{ 3, 0, 0 }, .result = 0, .use = .reusable, .regions = &.{0} } } }, .{ .product = &.{4} } },
    .constants = counted.constants,
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 5, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 3, 0, 0, 4, 6, 0, 0, 2, 0, 1, 4 } }, .result = 0, .regions = &.{0} },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .computation, .immediate = 0 }}, .terminator = .{ .with_region = .{ .region = 0, .body = 2, .arguments = &.{ 0, 1 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{
            .{ .destination = 3, .opcode = .cell_new, .operands = &.{ 0, 2 } },
            .{ .destination = 4, .opcode = .product, .operands = &.{3} },
            .{ .destination = 5, .opcode = .constant, .immediate = 0 },
            .{ .destination = 6, .opcode = .constant, .immediate = 1 },
            .{ .destination = 8, .opcode = .move, .operands = &.{2} },
        }, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 7, .opcode = .less, .operands = &.{ 5, 1 } }}, .terminator = .{ .branch = .{ .condition = 7, .when_true = .{ .block = 4 }, .when_false = .{ .block = 5 } } } },
        .{ .function = 1, .instructions = &.{
            .{ .destination = 10, .opcode = .field, .operands = &.{4}, .immediate = 0 },
            .{ .destination = 8, .opcode = .cell_get, .operands = &.{10} },
            .{ .destination = 8, .opcode = .integer_add, .operands = &.{ 8, 6 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 2 }} },
            .{ .destination = 9, .opcode = .cell_set, .operands = &.{ 3, 8 } },
            .{ .destination = 5, .opcode = .integer_add, .operands = &.{ 5, 6 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 2 }} },
        }, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 8 } },
    },
    .scopes = .{ .region_count = 1, .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 5 }},
};

test "nested loop motion retains the changing outer operand and each zero-trip guard" {
    var checked = try data.loop_motion.run(a, nested, null, .{});
    defer checked.deinit();
    var stats: data.closed_compilation.Statistics = .{};
    var shared = try data.closed_compilation.run(a, nested, .{ .contract = .semantic, .statistics = &stats });
    defer shared.deinit();
    var linked = try linkOriginal(nested);
    defer linked.deinit();
    std.debug.print("nested selection: {any}\n", .{stats});
    for ([_]u64{ 0, 1, 3 }) |outer| for ([_]u64{ 0, 1, 3, 16 }) |inner| {
        var expected: u64 = 0;
        for (0..@intCast(outer)) |i| if (inner % 2 == 1) {
            expected ^= @as(u64, @intCast(i)) ^ 0x1234;
        };
        const before = try execute(nested, &.{ outer, inner, 0x1234 }, expected);
        try std.testing.expectEqual(outer * inner * 2, before.xor_evaluations);
        for ([_]ir.Program{ checked.program, shared.program, linked.program }) |program| {
            const after = try execute(program, &.{ outer, inner, 0x1234 }, expected);
            try std.testing.expectEqual(outer * inner + outer, after.xor_evaluations);
            try std.testing.expectEqual(before.guards, after.guards);
        }
    };
}
test "aliasing mutable reads keep their evolving values under loop optimization" {
    var stats: data.loop_motion.Statistics = .{};
    var result = try data.loop_motion.run(a, mutable, &stats, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.hoisted);
    for ([_]u64{ 0, 1, 9 }) |n| for ([_]ir.Program{ mutable, result.program }) |program| {
        _ = try execute(program, &.{ n, 12 }, 12 + n);
    };
}
test "a potentially failing invariant remains absent on a zero-trip path" {
    var original = counted;
    var blocks = counted.blocks[0..4].*;
    var instructions = counted.blocks[2].instructions[0..3].*;
    instructions[0] = .{ .destination = 6, .opcode = .integer_div, .operands = &.{ 1, 2 }, .failures = &.{ .{ .kind = .arithmetic_overflow, .value = 2 }, .{ .kind = .division_by_zero, .value = 2 } } };
    blocks[2].instructions = &instructions;
    original.blocks = &blocks;
    var stats: data.loop_motion.Statistics = .{};
    var result = try data.loop_motion.run(a, original, &stats, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.hoisted);
    _ = try execute(original, &.{ 0, 1, 0 }, 0);
    _ = try execute(result.program, &.{ 0, 1, 0 }, 0);
    for ([_]ir.Program{ original, result.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var args: [24]u8 = @splat(0);
        args[0] = 1;
        args[8] = 1;
        var session = try world.Session.initImage(a, bytes, &args);
        defer session.deinit();
        const outcome = try session.run(null);
        try std.testing.expect(outcome == .failed);
        try std.testing.expectEqualSlices(u8, &.{}, try session.bytes(&outcome.failed));
    }
}

pub const yielding_infinite: ir.Program = .{
    .roots = counted.roots,
    .schemas = counted.schemas,
    .effects = &.{},
    .functions = counted.functions,
    .constants = &.{ counted.constants[0], counted.constants[1], counted.constants[2], .{ .schema = 2, .bytes = &.{1} } },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{ counted.blocks[0].instructions[0], counted.blocks[0].instructions[1], counted.blocks[0].instructions[2], .{ .destination = 5, .opcode = .constant, .immediate = 3 } }, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{}, .terminator = counted.blocks[1].terminator },
        .{ .function = 0, .instructions = counted.blocks[2].instructions[0..2], .terminator = .{ .yield_value = .{ .block = 1 } } },
        counted.blocks[3],
    },
};

test "infinite observed loop keeps successive public yields and same-image restore" {
    var stats: data.loop_motion.Statistics = .{};
    var checked = try data.loop_motion.run(a, yielding_infinite, &stats, .{});
    defer checked.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.hoisted);
    for ([_]ir.Program{ yielding_infinite, checked.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var args: [24]u8 = @splat(0);
        args[8] = 5;
        args[16] = 3;
        var session = try world.Session.initImage(a, bytes, &args);
        defer session.deinit();
        for (0..3) |_| {
            try std.testing.expect((try session.run(null)) == .yielded);
            const checkpoint = try session.checkpoint(a);
            defer a.free(checkpoint);
            const restored = try world.Session.restoreImage(a, bytes, checkpoint);
            session.deinit();
            session = restored;
            try session.resumeYield();
        }
    }
}
test "borrowed owners and cleanup-bearing source retain their original code" {
    inline for (.{ boundary.source.examples.borrowOperands, boundary.source.examples.unwind }) |example| {
        var builder = boundary.source.Builder.init(a);
        defer builder.deinit();
        var original = try boundary.program.compile(a, try example(&builder));
        defer original.deinit();
        var stats: data.loop_motion.Statistics = .{};
        var result = try data.loop_motion.run(a, original.program, &stats, .{});
        defer result.deinit();
        try std.testing.expectEqual(@as(usize, 0), stats.hoisted);
        try std.testing.expectEqual(try data.program_image.identity(a, original.program), try data.program_image.identity(a, result.program));
    }
}

pub const guarded: ir.Program = .{
    .roots = counted.roots,
    .schemas = counted.schemas,
    .constants = counted.constants,
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1, 2, 6 }, .layout = counted.functions[0].layout, .result = 0 }},
    .blocks = &.{ counted.blocks[0], counted.blocks[1], counted.blocks[2], .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 6 } } },
};

test "zero-trip visible values keep guarded placement while dead scalar work may speculate" {
    var stats: data.loop_motion.Statistics = .{};
    var checked = try data.loop_motion.run(a, guarded, &stats, .{});
    defer checked.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.guarded_entries);
    for ([_]u64{ 0, 1, 16 }) |n| {
        const expected: u64 = if (n == 0) 99 else 0x1234 ^ 0xabc;
        for ([_]ir.Program{ guarded, checked.program }) |program| {
            const observation = try execute(program, &.{ n, 0x1234, 0xabc, 99 }, expected);
            if (n == 0) try std.testing.expectEqual(@as(usize, 0), observation.xor_evaluations);
        }
    }
}
