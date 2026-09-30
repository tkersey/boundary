const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;
pub const repeated: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 0 },
    .schemas = &.{ .u64, .boolean },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 1, 0 } }, .result = 0 }},
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 1, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .integer_bit_not, .operands = &.{0} }}, .terminator = .{ .return_value = 2 } },
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .integer_bit_not, .operands = &.{0} }}, .terminator = .{ .return_value = 2 } },
    },
};

test "World preserves common-tail outputs and prior faults through source-free linking" {
    for (0..2) |fixture| {
        var original = repeated;
        var blocks = repeated.blocks[0..3].*;
        if (fixture == 1) {
            original.constants = &.{.{ .schema = 0, .bytes = &.{ 42, 0, 0, 0, 0, 0, 0, 0 } }};
            blocks[0].instructions = &.{.{ .destination = 2, .opcode = .integer_div, .operands = &.{ 0, 0 }, .failures = &.{ .{ .kind = .arithmetic_overflow, .value = 0 }, .{ .kind = .division_by_zero, .value = 0 } } }};
        }
        original.blocks = &blocks;
        var checked = try data.common_tails.run(a, original, null, .{});
        defer checked.deinit();
        var statistics: data.closed_compilation.Statistics = .{};
        var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic, .statistics = &statistics });
        defer compiled.deinit();
        try std.testing.expectEqual(.full, statistics.selected_candidate);
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "tails", .object = encoded }}, &.{}, .{ .instance = "tails", .symbol = "main" }, .{ .contract = .semantic });
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
                if (fixture == 1 and value == 0) {
                    try std.testing.expect(result.record == .failed);
                    try std.testing.expectEqual(@as(u64, 42), std.mem.readInt(u64, result.record.failed.value[0..8], .little));
                } else {
                    try std.testing.expect(result.record == .completed);
                    try std.testing.expectEqual(~value, std.mem.readInt(u64, result.record.completed[0..8], .little));
                }
            }
        };
    }
}
