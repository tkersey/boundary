const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const diamond: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 2 },
    .schemas = &.{ .u64, .boolean, .unit },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 1, 0, 0 } }, .result = 0 }},
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } }}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 4 } },
    },
};

fn execute(program: ir.Program, x: u64, y: u64, condition: bool, expected: u64) !void {
    const a = std.testing.allocator;
    var args: [17]u8 = undefined;
    std.mem.writeInt(u64, args[0..8], x, .little);
    std.mem.writeInt(u64, args[8..16], y, .little);
    args[16] = @intFromBool(condition);
    var result: [8]u8 = undefined;
    std.mem.writeInt(u64, &result, expected, .little);
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
    defer a.free(bytes);
    _ = try data.program_image.encode(a, program, bytes);
    var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
    defer outcome.deinit();
    try std.testing.expect(outcome.record == .completed);
    try std.testing.expectEqualSlices(u8, &result, outcome.record.completed);
}

test "World preserves both diamond paths after source-free expression reuse" {
    const a = std.testing.allocator;
    const object: data.component.Object = .{
        .program = diamond,
        .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }},
        .borrows = &.{.{ .function = 0 }},
    };
    const bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(bytes);
    _ = try data.component.encode(a, object, bytes);
    var linked = try data.linker.link(a, &.{.{ .key = "diamond", .object = bytes }}, &.{}, .{ .instance = "diamond", .symbol = "main" });
    defer linked.deinit();
    @memset(bytes, 0xff);
    var stats: data.expression_reuse.Statistics = .{};
    var result = try data.expression_reuse.run(a, linked.program, &stats, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.expressions_reused);
    try std.testing.expectEqual(@as(usize, 1), stats.across_blocks);
    for ([_][2]u64{ .{ 10, 21 }, .{ 0, 0 }, .{ 0xffffffffffffffff, 0x123456789abcdef0 } }) |pair| {
        for ([_]bool{ false, true }) |condition| {
            try execute(linked.program, pair[0], pair[1], condition, pair[0] ^ pair[1]);
            try execute(result.program, pair[0], pair[1], condition, pair[0] ^ pair[1]);
        }
    }
    std.debug.print("cross-CFG expression reuse: {d} -> {d} bytes; XOR evaluations 2 -> 1 on both paths\n", .{ try data.program_image.encodedLength(linked.program), try data.program_image.encodedLength(result.program) });
}

test "World observes the changed operand on only the mutating path" {
    const a = std.testing.allocator;
    var blocks = diamond.blocks[0..4].*;
    blocks[1].instructions = &.{.{ .destination = 0, .opcode = .move, .operands = &.{1} }};
    var original = diamond;
    original.blocks = &blocks;
    var stats: data.expression_reuse.Statistics = .{};
    var result = try data.expression_reuse.run(a, original, &stats, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.expressions_reused);
    for ([_]bool{ false, true }) |condition| {
        const expected: u64 = if (condition) 0 else 10 ^ 21;
        try execute(original, 10, 21, condition, expected);
        try execute(result.program, 10, 21, condition, expected);
    }
}

const private_cell: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .internal = .{ .region = 0 } }, .{ .internal = .{ .cell = .{ .element = 0, .region = 0 } } }, .{ .internal = .{ .computation = .{ .parameters = &.{ 2, 0, 0 }, .result = 0, .use = .reusable, .regions = &.{0} } } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 4, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 2, 0, 0, 3, 0, 1, 0 } }, .result = 0, .regions = &.{0} },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .computation, .immediate = 0 }}, .terminator = .{ .with_region = .{ .region = 0, .body = 2, .arguments = &.{ 0, 1 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{
            .{ .destination = 3, .opcode = .cell_new, .operands = &.{ 0, 1 } },
            .{ .destination = 4, .opcode = .cell_get, .operands = &.{3} },
            .{ .destination = 5, .opcode = .cell_set, .operands = &.{ 3, 2 } },
            .{ .destination = 6, .opcode = .cell_get, .operands = &.{3} },
        }, .terminator = .{ .return_value = 6 } },
    },
    .scopes = .{ .region_count = 1, .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 4 }},
};

test "World reads the new cell value after mutation with expression reuse enabled" {
    const a = std.testing.allocator;
    var stats: data.expression_reuse.Statistics = .{};
    var optimized = try data.expression_reuse.run(a, private_cell, &stats, .{});
    defer optimized.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.expressions_reused);
    for ([_]ir.Program{ private_cell, optimized.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{ 10, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0 } } });
        defer outcome.deinit();
        try std.testing.expect(outcome.record == .completed);
        try std.testing.expectEqualSlices(u8, &.{ 21, 0, 0, 0, 0, 0, 0, 0 }, outcome.record.completed);
    }
}
