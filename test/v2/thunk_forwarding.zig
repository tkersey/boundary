const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;
pub const wrapped: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .boolean, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{}, .result = 0, .capture_bound = &.{ 0, 2 }, .use = .reusable } } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 4 }, .layout = .{ .slots = &.{ 0, 2, 2, 0, 0, 2 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
        .{ .entry = 3, .inputs = &.{0}, .layout = .{ .slots = &.{ 2, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{
            .{ .destination = 1, .opcode = .computation, .operands = &.{0}, .immediate = 0 },
            .{ .destination = 5, .opcode = .computation, .operands = &.{4}, .immediate = 0 },
            .{ .destination = 2, .opcode = .computation, .operands = &.{1}, .immediate = 1 },
        }, .terminator = .{ .apply = .{ .computation = 2, .arguments = &.{}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 0, .arguments = &.{}, .next = .{ .block = 4, .assignments = &.{.{ .destination = 1, .source = .returned }} } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
    },
    .constructors = &.{ .{ .function = 1, .capture = 0, .schema = 2 }, .{ .function = 2, .capture = 1, .schema = 2 } },
    .scopes = .{ .captures = &.{ .{ .fields = &.{0}, .use = .reusable }, .{ .fields = &.{2}, .use = .reusable } } },
};

test "forwarded partial thunks preserve demanded failure and divergence" {
    for ([_]bool{ false, true }) |diverges| {
        var original = wrapped;
        var functions = wrapped.functions[0..3].*;
        var blocks = wrapped.blocks[0..5].*;
        original.functions = &functions;
        original.blocks = &blocks;
        if (diverges) {
            blocks[2].terminator = .{ .jump = .{ .block = 2 } };
        } else {
            functions[1].layout.slots = &.{ 0, 1 };
            original.constants = &.{.{ .schema = 1, .bytes = &.{} }};
            blocks[2].instructions = &.{.{ .destination = 1, .opcode = .constant }};
            blocks[2].terminator = .{ .fail = 1 };
        }
        var stats: data.thunk_forwarding.Statistics = .{};
        var checked = try data.thunk_forwarding.run(a, original, &stats, .{});
        defer checked.deinit();
        try std.testing.expectEqual(@as(usize, 1), stats.wrappers_removed);
        var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
        defer compiled.deinit();
        for ([_]ir.Program{ original, checked.program, compiled.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{ 1, 0 } }, .quantum = 64 });
            defer result.deinit();
            if (diverges) {
                try std.testing.expect(result.record == .progressed);
                const resumed = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = result.record.progressed.? }, .quantum = 64 });
                result.deinit();
                result = resumed;
                try std.testing.expect(result.record == .progressed);
            } else {
                try std.testing.expect(result.record == .failed);
                try std.testing.expectEqualSlices(u8, &.{}, result.record.failed.value);
            }
        }
    }
}
