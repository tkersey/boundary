const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
pub const captured: ir.Program = .{
    .roots = .{ .entry = 0, .result = 3, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 3, .capture_bound = &.{0}, .use = .linear } } }, .{ .product = &.{ 0, 0 } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 2, 3 } }, .result = 3 },
        .{ .entry = 2, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 3 } }, .result = 3 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .computation, .operands = &.{0}, .immediate = 0 }}, .terminator = .{ .apply = .{ .computation = 2, .arguments = &.{1}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 2, .opcode = .product, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 2 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{0}, .use = .linear }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 2 }},
};

test "independent World executes captured arguments in order before and after specialization" {
    const a = std.testing.allocator;
    var optimized = try data.application_specialization.run(a, captured, null, .{});
    defer optimized.deinit();
    for ([_][2]u64{ .{ 10, 21 }, .{ 42, 3 }, .{ 0, 999 } }) |pair| {
        var args: [16]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], pair[0], .little);
        std.mem.writeInt(u64, args[8..16], pair[1], .little);
        for ([_]ir.Program{ captured, optimized.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer outcome.deinit();
            try std.testing.expect(outcome.record == .completed);
            try std.testing.expectEqualSlices(u8, &args, outcome.record.completed);
        }
    }
}
