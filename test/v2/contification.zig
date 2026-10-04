const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;
pub const shared: ir.Program = .{
    .roots = .{ .entry = 0, .result = 2, .failure = 3 },
    .schemas = &.{ .u64, .boolean, .{ .product = &.{ 0, 0 } }, .unit },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 0, 0, 1, 1, 2 } }, .result = 2 },
        .{ .entry = 4, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 1, 2 } }, .result = 2 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 1, 3 }, .next = .{ .block = 3, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 1, 0, 3 }, .next = .{ .block = 3, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 5, .assignments = &.{ .{ .destination = 0, .source = .{ .slot = 1 } }, .{ .destination = 1, .source = .{ .slot = 0 } } } }, .when_false = .{ .block = 5 } } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 3, .opcode = .product, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 3 } },
    },
};

test "World preserves shared join returns and simultaneous swaps through closed linking" {
    var checked = try data.contification.run(a, shared, null, .{});
    defer checked.deinit();
    var statistics: data.closed_compilation.Statistics = .{};
    var compiled = try data.closed_compilation.run(a, shared, .{ .contract = .semantic, .statistics = &statistics });
    defer compiled.deinit();
    try std.testing.expectEqual(.full, statistics.selected_candidate);
    try std.testing.expectEqual(@as(usize, 1), compiled.program.functions.len);
    const object: data.component.Object = .{ .program = shared, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 } } };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "join", .object = encoded }}, &.{}, .{ .instance = "join", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(encoded, 0xff);
    for ([_][2]u64{ .{ 0, 1 }, .{ 7, 11 }, .{ std.math.maxInt(u64), 0 } }) |words| for ([_]bool{ false, true }) |first| for ([_]bool{ false, true }) |second| {
        var args: [18]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], words[0], .little);
        std.mem.writeInt(u64, args[8..16], words[1], .little);
        args[16] = @intFromBool(first);
        args[17] = @intFromBool(second);
        var expected: [16]u8 = undefined;
        std.mem.writeInt(u64, expected[0..8], words[@intFromBool(first == second)], .little);
        std.mem.writeInt(u64, expected[8..16], words[@intFromBool(first != second)], .little);
        for ([_]ir.Program{ shared, checked.program, compiled.program, linked.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer result.deinit();
            try std.testing.expect(result.record == .completed);
            try std.testing.expectEqualSlices(u8, &expected, result.record.completed);
        }
    };
}

pub const mutual: ir.Program = .{
    .roots = .{ .entry = 0, .result = 2, .failure = 3 },
    .schemas = &.{ .u64, .boolean, .{ .product = &.{ 0, 0 } }, .unit },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 0, 0, 1, 1, 2 } }, .result = 2 },
        .{ .entry = 4, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 1, 2 } }, .result = 2 },
        .{ .entry = 8, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 1, 2 } }, .result = 2 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 1, 3 }, .next = .{ .block = 3, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 2, .arguments = &.{ 0, 1, 3 }, .next = .{ .block = 3, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 5 }, .when_false = .{ .block = 7 } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .call = .{ .function = 2, .arguments = &.{ 0, 1, 2 }, .next = .{ .block = 6, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 3, .opcode = .product, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 3 } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 9 }, .when_false = .{ .block = 11 } } } },
        .{ .function = 2, .instructions = &.{.{ .destination = 2, .opcode = .boolean_not, .operands = &.{2} }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 1, 0, 2 }, .next = .{ .block = 10, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 2, .instructions = &.{.{ .destination = 3, .opcode = .product, .operands = &.{ 1, 0 } }}, .terminator = .{ .return_value = 3 } },
    },
};

test "World executes actual A to B to A recursion after closed-link contification" {
    var checked = try data.contification.run(a, mutual, null, .{});
    defer checked.deinit();
    var statistics: data.closed_compilation.Statistics = .{};
    var compiled = try data.closed_compilation.run(a, mutual, .{ .contract = .semantic, .statistics = &statistics });
    defer compiled.deinit();
    try std.testing.expectEqual(.full, statistics.selected_candidate);
    const object: data.component.Object = .{ .program = mutual, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 } } };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "recursive", .object = encoded }}, &.{}, .{ .instance = "recursive", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(encoded, 0xff);
    for ([_][2]u64{ .{ 0, 1 }, .{ 7, 11 }, .{ std.math.maxInt(u64), 0 } }) |words| for ([_]bool{ false, true }) |first| for ([_]bool{ false, true }) |second| {
        var args: [18]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], words[0], .little);
        std.mem.writeInt(u64, args[8..16], words[1], .little);
        args[16] = @intFromBool(first);
        args[17] = @intFromBool(second);
        const swapped = !first or second;
        var expected: [16]u8 = undefined;
        std.mem.writeInt(u64, expected[0..8], words[@intFromBool(swapped)], .little);
        std.mem.writeInt(u64, expected[8..16], words[@intFromBool(!swapped)], .little);
        for ([_]ir.Program{ mutual, checked.program, compiled.program, linked.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer result.deinit();
            try std.testing.expect(result.record == .completed);
            try std.testing.expectEqualSlices(u8, &expected, result.record.completed);
        }
    };
}
test "contified recursive control retains nonterminating finite prefixes" {
    var original = mutual;
    var blocks = mutual.blocks[0..12].*;
    blocks[9].instructions = &.{};
    original.blocks = &blocks;
    var candidate = try data.contification.run(a, original, null, .{});
    defer candidate.deinit();
    var args = @as([18]u8, @splat(0));
    args[16] = 1;
    args[17] = 1;
    for ([_]ir.Program{ original, candidate.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args }, .quantum = 32 });
        defer result.deinit();
        try std.testing.expect(result.record == .progressed);
    }
}

pub const returned: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{0}, .use = .reusable } } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 2, 0 } }, .result = 0 },
        .{ .entry = 3, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 2 } }, .result = 2 },
        .{ .entry = 4, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{0}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 2, .arguments = &.{1}, .next = .{ .block = 2, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 1, .opcode = .computation, .operands = &.{0}, .immediate = 0 }}, .terminator = .{ .return_value = 1 } },
        .{ .function = 2, .instructions = &.{.{ .destination = 2, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 2 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{0}, .use = .reusable }} },
    .constructors = &.{.{ .function = 2, .capture = 0, .schema = 2 }},
};
pub const retained: ir.Program = .{
    .roots = returned.roots,
    .schemas = returned.schemas,
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        returned.functions[0],
        .{ .entry = 2, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 },
        .{ .entry = 4, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .computation, .operands = &.{0}, .immediate = 0 }}, .terminator = .{ .handle = .{ .handler = 0, .body = 2, .arguments = &.{1}, .state = &.{}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .yield_value = .{ .block = 3 } } },
        .{ .function = 1, .instructions = returned.blocks[4].instructions, .terminator = .{ .return_value = 2 } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
    },
    .handlers = &.{.{ .mode = .deep, .input = 0, .answer = 0, .return_function = 2, .clauses = &.{} }},
    .scopes = returned.scopes,
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 2 }},
};

test "World retains returned helper values and handler captures across yield" {
    for ([_]ir.Program{ returned, retained }, 0..) |original, fixture| {
        var candidate = try data.contification.run(a, original, null, .{});
        defer candidate.deinit();
        for ([_][2]u64{ .{ 0, 1 }, .{ 7, 11 }, .{ std.math.maxInt(u64), 0 } }) |words| {
            var args: [16]u8 = undefined;
            std.mem.writeInt(u64, args[0..8], words[0], .little);
            std.mem.writeInt(u64, args[8..16], words[1], .little);
            for ([_]ir.Program{ original, candidate.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var first = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
                defer first.deinit();
                if (fixture == 0) {
                    try std.testing.expect(first.record == .completed);
                    try std.testing.expectEqual(words[0] ^ words[1], std.mem.readInt(u64, first.record.completed[0..8], .little));
                } else {
                    try std.testing.expect(first.record == .yielded);
                    var resumed = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = first.record.yielded.? }, .control = .resume_yield });
                    defer resumed.deinit();
                    try std.testing.expect(resumed.record == .completed);
                    try std.testing.expectEqual(words[0] ^ words[1], std.mem.readInt(u64, resumed.record.completed[0..8], .little));
                }
            }
        }
    }
}
