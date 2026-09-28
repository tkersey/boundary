const std = @import("std");
const world = @import("world");
const data = @import("boundary_data");
const ir = data.activation;
const image = data.program_image;
const affine = data.affine_state;
const fixture: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .boolean, .{ .internal = .{ .computation = .{ .parameters = &.{ 0, 2 }, .result = 0, .capture_bound = &.{0}, .use = .reusable } } } },
    .constants = &.{.{ .schema = 2, .bytes = &.{0} }},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2, 3, 4 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 2, 3, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1, 2, 3, 4 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 2, 0, 2, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 5, .opcode = .computation, .operands = &.{ 0, 1, 2 }, .immediate = 0 }}, .terminator = .{ .apply = .{ .computation = 5, .arguments = &.{ 3, 4 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 6, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 6 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 4, .when_true = .{ .block = 3 }, .when_false = .{ .block = 5 } } } },
        .{ .function = 1, .instructions = &.{
            .{ .destination = 5, .opcode = .integer_bit_xor, .operands = &.{ 0, 3 } },
            .{ .destination = 6, .opcode = .constant, .immediate = 0 },
        }, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 1, 2, 5, 3, 6 }, .next = .{ .block = 4, .assignments = &.{.{ .destination = 7, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 7 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 5, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 5 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{ 0, 0, 0 }, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 3 }},
};

test "World executes original and reduced private capture interfaces" {
    const a = std.testing.allocator;
    var candidate = try affine.run(a, fixture, 0, null, 100000, .{});
    defer candidate.deinit();
    for ([_][4]u64{ .{ 0, 0, 0, 0 }, .{ 1, 2, 4, 8 }, .{ 0x123456789abcdef0, 0xfedcba9876543210, 0xffffffffffffffff, 23 } }) |words| {
        for ([_]bool{ false, true }) |rotate| {
            var args: [33]u8 = undefined;
            for (words, 0..) |word, i| std.mem.writeInt(u64, args[i * 8 ..][0..8], word, .little);
            args[32] = @intFromBool(rotate);
            var expected: [8]u8 = undefined;
            std.mem.writeInt(u64, &expected, if (rotate) words[1] ^ words[2] else words[0] ^ words[1], .little);
            for ([_]@TypeOf(fixture){ fixture, candidate.program }) |program| {
                const bytes = try a.alloc(u8, try image.encodedLength(program));
                defer a.free(bytes);
                _ = try image.encode(a, program, bytes);
                var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
                defer outcome.deinit();
                try std.testing.expect(outcome.record == .completed);
                try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
            }
        }
    }
}

fn recurrentFixture() ir.Program {
    var program = fixture;
    program.schemas = &.{ fixture.schemas[0], fixture.schemas[1], fixture.schemas[2], .{ .internal = .{ .computation = .{ .parameters = &.{ 0, 4 }, .result = 0, .capture_bound = &.{0}, .use = .reusable } } }, .u8 };
    program.constants = &.{
        .{ .schema = 4, .bytes = &.{0} },
        .{ .schema = 4, .bytes = &.{1} },
        .{ .schema = 1, .bytes = &.{} },
        .{ .schema = 0, .bytes = &.{ 0xa5, 0, 0, 0, 0, 0, 0, 0 } },
    };
    program.functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2, 3, 4 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 4, 3, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1, 2, 3, 4 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 4, 0, 4, 0, 4, 2, 0, 0 } }, .result = 0 },
    };
    program.blocks = &.{
        fixture.blocks[0], fixture.blocks[1],
        .{ .function = 1, .instructions = &.{
            .{ .destination = 8, .opcode = .constant, .immediate = 0 },
            .{ .destination = 9, .opcode = .equal, .operands = &.{ 4, 8 } },
        }, .terminator = .{ .branch = .{ .condition = 9, .when_true = .{ .block = 5 }, .when_false = .{ .block = 3 } } } },
        .{ .function = 1, .instructions = &.{
            .{ .destination = 8, .opcode = .constant, .immediate = 1 },
            .{ .destination = 6, .opcode = .integer_sub, .operands = &.{ 4, 8 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 2 }} },
            .{ .destination = 5, .opcode = .integer_bit_xor, .operands = &.{ 0, 3 } },
            .{ .destination = 10, .opcode = .constant, .immediate = 3 },
            .{ .destination = 5, .opcode = .integer_bit_xor, .operands = &.{ 5, 10 } },
        }, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 1, 2, 5, 3, 6 }, .next = .{ .block = 4, .assignments = &.{.{ .destination = 7, .source = .returned }} } } } },
        fixture.blocks[4],
        .{ .function = 1, .instructions = &.{
            .{ .destination = 5, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } },
            .{ .destination = 10, .opcode = .constant, .immediate = 3 },
            .{ .destination = 5, .opcode = .integer_bit_xor, .operands = &.{ 5, 3 } },
            .{ .destination = 11, .opcode = .integer_bit_xor, .operands = &.{ 5, 10 } },
        }, .terminator = .{ .return_value = 11 } },
    };
    return program;
}

test "checked affine capture cycle preserves repeated dynamic input and offsets" {
    const a = std.testing.allocator;
    const original = comptime recurrentFixture();
    var stats: affine.Statistics = .{};
    var candidate = try affine.run(a, original, 0, &stats, 100000, .{});
    defer candidate.deinit();
    try std.testing.expectEqual(.applied, stats.outcome);
    try std.testing.expectEqual(@as(usize, 2), stats.reduced_words);
    for ([_][4]u64{ .{ 0, 0, 0, 0 }, .{ 1, 2, 4, 8 }, .{ 0x123456789abcdef0, 0xfedcba9876543210, 0xffffffffffffffff, 23 } }) |words| {
        for ([_]u8{ 0, 1, 2, 3, 8, 31 }) |count| {
            var state = words[0..3].*;
            for (0..count) |_| {
                const old_p = state[0];
                const old_q = state[1];
                const old_r = state[2];
                state[0] = old_q;
                state[1] = old_r;
                state[2] = old_p ^ words[3] ^ 0xa5;
            }
            var expected: [8]u8 = undefined;
            std.mem.writeInt(u64, &expected, state[0] ^ state[1] ^ words[3] ^ 0xa5, .little);
            var args: [33]u8 = undefined;
            for (words, 0..) |word, i| std.mem.writeInt(u64, args[i * 8 ..][0..8], word, .little);
            args[32] = count;
            for ([_]ir.Program{ original, candidate.program }, 0..) |program, arm| {
                const bytes = try a.alloc(u8, try image.encodedLength(program));
                defer a.free(bytes);
                _ = try image.encode(a, program, bytes);
                var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
                defer outcome.deinit();
                try std.testing.expect(outcome.record == .completed);
                if (!std.mem.eql(u8, &expected, outcome.record.completed)) std.debug.print("words={any} count={d} arm={d}\n", .{ words, count, arm });
                try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
            }
        }
    }
}
