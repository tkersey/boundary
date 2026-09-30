const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
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

test "source-free cell scalar replacement preserves successive stored values" {
    const a = std.testing.allocator;
    var original = private_cell;
    var blocks = private_cell.blocks[0..3].*;
    blocks[2].instructions = &.{ private_cell.blocks[2].instructions[0], .{ .destination = 5, .opcode = .cell_set, .operands = &.{ 3, 1 } }, private_cell.blocks[2].instructions[2], private_cell.blocks[2].instructions[3] };
    original.blocks = &blocks;
    const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
    const object_bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(object_bytes);
    _ = try data.component.encode(a, object, object_bytes);
    var linked = try data.linker.link(a, &.{.{ .key = "cell", .object = object_bytes }}, &.{}, .{ .instance = "cell", .symbol = "main" });
    defer linked.deinit();
    @memset(object_bytes, 0xff);
    var stats: data.cell_reduction.Statistics = .{};
    var scalar = try data.cell_reduction.run(a, linked.program, &stats, .{});
    defer scalar.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.cells_removed);
    try std.testing.expectEqual(@as(usize, 2), stats.stores_removed);
    var result = try data.dead_computation.run(a, scalar.program, null, .{});
    defer result.deinit();
    for ([_][2]u64{ .{ 10, 21 }, .{ 0, 999 }, .{ 0xffffffffffffffff, 0x123456789abcdef0 } }) |pair| {
        var args: [16]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], pair[0], .little);
        std.mem.writeInt(u64, args[8..16], pair[1], .little);
        var expected: [8]u8 = undefined;
        std.mem.writeInt(u64, &expected, pair[1], .little);
        for ([_]ir.Program{ linked.program, result.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer outcome.deinit();
            try std.testing.expect(outcome.record == .completed);
            try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
        }
    }
    std.debug.print("linked private cell: {d} -> {d} bytes; allocations 1 -> 0, stores 2 -> 0\n", .{ try data.program_image.encodedLength(linked.program), try data.program_image.encodedLength(result.program) });
}
