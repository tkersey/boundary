const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const patterns = data.call_patterns;
const a = std.testing.allocator;
pub const repeated: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 2 },
    .schemas = &.{ .u64, .boolean, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{0}, .use = .reusable } } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 0, 0, 1, 1, 3, 0 } }, .result = 0 },
        .{ .entry = 6, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 3, 0, 0, 0, 0, 0 } }, .result = 0 },
        .{ .entry = 9, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
        .{ .entry = 10, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .computation, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 4, 0, 1 }, .next = .{ .block = 5, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 3, .when_true = .{ .block = 3 }, .when_false = .{ .block = 4 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .computation, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 4, 0, 1 }, .next = .{ .block = 5, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .computation, .immediate = 1 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 4, 0, 1 }, .next = .{ .block = 5, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 5 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 0, .arguments = &.{1}, .next = .{ .block = 7, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 0, .arguments = &.{2}, .next = .{ .block = 8, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 5, .opcode = .integer_bit_or, .operands = &.{ 3, 4 } }}, .terminator = .{ .return_value = 5 } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 3, .instructions = &.{.{ .destination = 1, .opcode = .integer_bit_not, .operands = &.{0} }}, .terminator = .{ .return_value = 1 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
    .constructors = &.{ .{ .function = 2, .capture = 0, .schema = 3 }, .{ .function = 3, .capture = 0, .schema = 3 } },
};

test "World executes repeated callable workers through compilation and closed linking" {
    var direct = try patterns.run(a, repeated, null, .{});
    defer direct.deinit();
    var statistics: data.closed_compilation.Statistics = .{};
    var compiled = try data.closed_compilation.run(a, repeated, .{ .contract = .semantic, .statistics = &statistics });
    defer compiled.deinit();
    try std.testing.expectEqual(.full, statistics.selected_candidate);
    const object: data.component.Object = .{ .program = repeated, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 }, .{ .function = 3 } } };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "patterns", .object = encoded }}, &.{}, .{ .instance = "patterns", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(encoded, 0xff);
    for ([_][2]u64{ .{ 1, 2 }, .{ 7, 11 }, .{ std.math.maxInt(u64), std.math.maxInt(u64) } }) |words| for ([_]bool{ false, true }) |first| for ([_]bool{ false, true }) |second| {
        var args: [18]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], words[0], .little);
        std.mem.writeInt(u64, args[8..16], words[1], .little);
        args[16] = @intFromBool(first);
        args[17] = @intFromBool(second);
        const expected = if (first or second) words[0] | words[1] else (~words[0]) | (~words[1]);
        for ([_]ir.Program{ repeated, direct.program, compiled.program, linked.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer result.deinit();
            try std.testing.expect(result.record == .completed);
            try std.testing.expectEqual(expected, std.mem.readInt(u64, result.record.completed[0..8], .little));
        }
    };
}

pub const leaf_product: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .product = &.{ 0, 0 } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 2, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{0}, .layout = .{ .slots = &.{ 2, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .product, .operands = &.{ 0, 1 } }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{2}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 1, .opcode = .field, .operands = &.{0}, .immediate = 1 }}, .terminator = .{ .return_value = 1 } },
    },
};

pub const leaf_overwrite: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{0}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 1, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 2 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 0, .opcode = .integer_bit_not, .operands = &.{0} }}, .terminator = .{ .return_value = 0 } },
    },
};

test "World preserves leaf substitution and product cancellation" {
    for ([_]ir.Program{ leaf_product, leaf_overwrite }, 0..) |original, fixture| {
        var candidate = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
        defer candidate.deinit();
        for ([_]u64{ 0, 1, 0xfedcba9876543210 }) |word| {
            var args: [16]u8 = undefined;
            std.mem.writeInt(u64, args[0..8], word, .little);
            std.mem.writeInt(u64, args[8..16], ~word, .little);
            const expected = if (fixture == 0) ~word else std.math.maxInt(u64);
            for ([_]ir.Program{ original, candidate.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = args[0..if (fixture == 0) @as(usize, 16) else 8] } });
                defer result.deinit();
                try std.testing.expect(result.record == .completed);
                try std.testing.expectEqual(expected, std.mem.readInt(u64, result.record.completed[0..8], .little));
            }
        }
    }
}
