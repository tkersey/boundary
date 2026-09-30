const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const original: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .product = &.{ 0, 0 } } },
    .constants = &.{.{ .schema = 0, .bytes = &.{ 99, 0, 0, 0, 0, 0, 0, 0 } }},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 2, 0, 0, 0, 2 } }, .result = 0 }},
    .blocks = &.{.{ .function = 0, .instructions = &.{
        .{ .destination = 2, .opcode = .product, .operands = &.{ 0, 1 } },
        .{ .destination = 3, .opcode = .field, .operands = &.{2}, .immediate = 0 },
        .{ .destination = 4, .opcode = .field, .operands = &.{2}, .immediate = 1 },
        .{ .destination = 5, .opcode = .integer_bit_xor, .operands = &.{ 3, 4 } },
    }, .terminator = .{ .return_value = 5 } }},
};

test "source-free closed object linking retains the product reduction opportunity" {
    const a = std.testing.allocator;
    const object: data.component.Object = .{
        .program = original,
        .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }},
        .borrows = &.{.{ .function = 0 }},
    };
    const object_bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(object_bytes);
    _ = try data.component.encode(a, object, object_bytes);
    var linked = try data.linker.link(a, &.{.{ .key = "product", .object = object_bytes }}, &.{}, .{ .instance = "product", .symbol = "main" });
    defer linked.deinit();
    // The optimizer consumes only the independently decoded linked records.
    @memset(object_bytes, 0xff);
    var stats: data.aggregate_reduction.Statistics = .{};
    var forwarded = try data.aggregate_reduction.run(a, linked.program, &stats, .{});
    defer forwarded.deinit();
    try std.testing.expectEqual(@as(usize, 2), stats.fields_forwarded);
    var p01: data.coalescing.Statistics = .{};
    var optimized = try data.dead_computation.run(a, forwarded.program, null, .{ .coalescing = .{ .statistics = &p01 } });
    defer optimized.deinit();
    try std.testing.expect(p01.outcome != .not_run);
    for ([_][2]u64{ .{ 0, 1 }, .{ 42, 99 }, .{ 0xffffffffffffffff, 0x123456789abcdef0 } }) |pair| {
        var args: [16]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], pair[0], .little);
        std.mem.writeInt(u64, args[8..16], pair[1], .little);
        var expected: [8]u8 = undefined;
        std.mem.writeInt(u64, &expected, pair[0] ^ pair[1], .little);
        for ([_]ir.Program{ linked.program, optimized.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer outcome.deinit();
            try std.testing.expect(outcome.record == .completed);
            try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
        }
    }
}
