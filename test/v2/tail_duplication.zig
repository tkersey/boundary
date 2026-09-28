const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;
pub const split: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 0 },
    .schemas = &.{ .u64, .boolean },
    .constants = &.{ .{ .schema = 1, .bytes = &.{1} }, .{ .schema = 1, .bytes = &.{0} } },
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 1, 1, 0 } }, .result = 0 }},
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 1, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .constant, .immediate = 1 }}, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .integer_bit_not, .operands = &.{0} }}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 4 }, .when_false = .{ .block = 5 } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
    },
};
pub const cell_effect: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .internal = .{ .region = 0 } }, .{ .internal = .{ .cell = .{ .element = 0, .region = 0 } } }, .{ .internal = .{ .computation = .{ .parameters = &.{ 2, 0, 5 }, .result = 0, .use = .reusable, .regions = &.{0} } } }, .boolean },
    .constants = &.{ .{ .schema = 5, .bytes = &.{1} }, .{ .schema = 5, .bytes = &.{0} } },
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 5, 4, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 2, 0, 5, 3, 0, 1, 5, 0 } }, .result = 0, .regions = &.{0} },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .computation, .immediate = 0 }}, .terminator = .{ .with_region = .{ .region = 0, .body = 2, .arguments = &.{ 0, 1 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 3, .opcode = .cell_new, .operands = &.{ 0, 1 } }}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 3 }, .when_false = .{ .block = 4 } } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 6, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .jump = .{ .block = 5 } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 6, .opcode = .constant, .immediate = 1 }}, .terminator = .{ .jump = .{ .block = 5 } } },
        .{ .function = 1, .instructions = &.{ .{ .destination = 4, .opcode = .cell_get, .operands = &.{3} }, .{ .destination = 4, .opcode = .integer_bit_not, .operands = &.{4} }, .{ .destination = 5, .opcode = .cell_set, .operands = &.{ 3, 4 } } }, .terminator = .{ .branch = .{ .condition = 6, .when_true = .{ .block = 6 }, .when_false = .{ .block = 7 } } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 7, .opcode = .cell_get, .operands = &.{3} }}, .terminator = .{ .return_value = 7 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 7, .opcode = .cell_get, .operands = &.{3} }}, .terminator = .{ .return_value = 7 } },
    },
    .scopes = .{ .region_count = 1, .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 4 }},
};

test "World observes duplicated tails and one cell mutation per path after source-free link" {
    for ([_]ir.Program{ split, cell_effect }, 0..) |original, fixture| {
        var checked = try data.tail_duplication.run(a, original, null, .{});
        defer checked.deinit();
        var statistics: data.closed_compilation.Statistics = .{};
        var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic, .statistics = &statistics });
        defer compiled.deinit();
        try std.testing.expectEqual(.full, statistics.selected_candidate);
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = if (fixture == 0) &.{.{ .function = 0 }} else &.{ .{ .function = 0 }, .{ .function = 1 } } };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "duplicate", .object = encoded }}, &.{}, .{ .instance = "duplicate", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        for ([_]u64{ 0, 7, std.math.maxInt(u64) }) |value| for ([_]bool{ false, true }) |branch| {
            var args: [9]u8 = undefined;
            std.mem.writeInt(u64, args[0..8], value, .little);
            args[8] = @intFromBool(branch);
            for ([_]ir.Program{ original, checked.program, compiled.program, linked.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
                defer result.deinit();
                try std.testing.expect(result.record == .completed);
                try std.testing.expectEqual(if (fixture == 1 or branch) ~value else value, std.mem.readInt(u64, result.record.completed[0..8], .little));
            }
        };
    }
}
