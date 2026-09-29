const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;
pub const interaction: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0, 0 } }, .result = 0 }},
    .blocks = &.{.{ .function = 0, .instructions = &.{
        .{ .destination = 2, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } },
        .{ .destination = 3, .opcode = .integer_bit_xor, .operands = &.{ 2, 0 } },
    }, .terminator = .{ .return_value = 3 } }},
};

test "interacting equality laws execute at each width through shared and source-free compilation" {
    for ([_]data.program.Schema{ .u8, .u16, .u32, .u64 }, 0..) |schema, index| {
        var original = interaction;
        const schemas = [_]data.program.Schema{ schema, .unit };
        original.schemas = &schemas;
        var direct = try data.equality_saturation.run(a, original, null, .{});
        defer direct.deinit();
        var stats: data.closed_compilation.Statistics = .{};
        var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic, .statistics = &stats });
        defer shared.deinit();
        try std.testing.expectEqual(data.closed_compilation.Outcome.applied, stats.outcome);
        try std.testing.expectEqual(@as(usize, 0), shared.program.blocks[0].instructions.len);
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "xor", .object = encoded }}, &.{}, .{ .instance = "xor", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        const size = @as(usize, 1) << @as(u3, @intCast(index));
        for ([_]u64{ 0, 1, 0x123456789abcdef0, std.math.maxInt(u64) }) |left| for ([_]u64{ 0, 7, 0xfedcba9876543210, std.math.maxInt(u64) }) |right| {
            var input: [16]u8 = undefined;
            for (0..size) |byte| {
                input[byte] = @truncate(left >> @as(u6, @intCast(byte * 8)));
                input[size + byte] = @truncate(right >> @as(u6, @intCast(byte * 8)));
            }
            for ([_]ir.Program{ original, direct.program, shared.program, linked.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var session = try world.Session.initImage(a, bytes, input[0 .. 2 * size]);
                defer session.deinit();
                var steps: usize = 0;
                while (true) {
                    steps += 1;
                    try std.testing.expect(steps < 10);
                    switch (try session.run(1)) {
                        .progressed => {
                            const checkpoint = try session.checkpoint(a);
                            defer a.free(checkpoint);
                            const restored = try world.Session.restoreImage(a, bytes, checkpoint);
                            session.deinit();
                            session = restored;
                        },
                        .completed => |value| {
                            try std.testing.expectEqualSlices(u8, input[size .. 2 * size], try session.bytes(&value));
                            break;
                        },
                        else => return error.UnexpectedOutcome,
                    }
                }
            }
        };
    }
}
test "zero times a failing checked expression still fails in shared compilation" {
    var original = interaction;
    original.constants = &.{ .{ .schema = 1, .bytes = &.{} }, .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } } };
    original.blocks = &.{.{ .function = 0, .instructions = &.{ .{ .destination = 2, .opcode = .constant, .immediate = 1 }, .{ .destination = 3, .opcode = .integer_add, .operands = &.{ 0, 1 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 0 }} }, .{ .destination = 2, .opcode = .integer_mul, .operands = &.{ 2, 3 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 0 }} } }, .terminator = .{ .return_value = 2 } }};
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer shared.deinit();
    var input = [_]u8{0} ** 16;
    @memset(input[0..8], 255);
    input[8] = 1;
    for ([_]ir.Program{ original, shared.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &input } });
        defer result.deinit();
        try std.testing.expect(result.record == .failed);
        try std.testing.expectEqualSlices(u8, &.{}, result.record.failed.value);
    }
}

pub const projected: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .product = &.{ 0, 0 } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 2, 0, 0, 0 } }, .result = 0 }},
    .blocks = &.{.{ .function = 0, .instructions = &.{
        .{ .destination = 2, .opcode = .product, .operands = &.{ 0, 1 } },
        .{ .destination = 3, .opcode = .field, .operands = &.{2}, .immediate = 0 },
        .{ .destination = 4, .opcode = .integer_bit_xor, .operands = &.{ 3, 1 } },
        .{ .destination = 5, .opcode = .integer_bit_xor, .operands = &.{ 4, 0 } },
    }, .terminator = .{ .return_value = 5 } }},
};
pub const shared_product: ir.Program = .{
    .roots = .{ .entry = 0, .result = 3, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .product = &.{ 0, 0 } }, .{ .product = &.{ 2, 2 } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 2, 3, 2, 3 } }, .result = 3 }},
    .blocks = &.{.{ .function = 0, .instructions = &.{
        .{ .destination = 2, .opcode = .product, .operands = &.{ 0, 1 } },
        .{ .destination = 3, .opcode = .product, .operands = &.{ 2, 2 } },
        .{ .destination = 4, .opcode = .field, .operands = &.{3}, .immediate = 0 },
        .{ .destination = 5, .opcode = .product, .operands = &.{ 2, 4 } },
    }, .terminator = .{ .return_value = 5 } }},
};

test "product projection and shared construction execute through direct and final-link saturation" {
    for ([_]ir.Program{ projected, shared_product }, 0..) |original, kind| {
        var direct = try data.equality_saturation.run(a, original, null, .{});
        defer direct.deinit();
        var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
        defer shared.deinit();
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "products", .object = encoded }}, &.{}, .{ .instance = "products", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        for ([_]u64{ 0, 17, std.math.maxInt(u64) }) |left| for ([_]u64{ 7, 0xfedcba9876543210 }) |right| {
            var args: [16]u8 = undefined;
            std.mem.writeInt(u64, args[0..8], left, .little);
            std.mem.writeInt(u64, args[8..16], right, .little);
            var expected: [32]u8 = undefined;
            @memcpy(expected[0..16], &args);
            @memcpy(expected[16..32], &args);
            for ([_]ir.Program{ original, direct.program, shared.program, linked.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var session = try world.Session.initImage(a, bytes, &args);
                defer session.deinit();
                var steps: usize = 0;
                while (true) {
                    steps += 1;
                    try std.testing.expect(steps < 16);
                    switch (try session.run(1)) {
                        .progressed => {
                            const checkpoint = try session.checkpoint(a);
                            defer a.free(checkpoint);
                            const restored = try world.Session.restoreImage(a, bytes, checkpoint);
                            session.deinit();
                            session = restored;
                        },
                        .completed => |value| {
                            try std.testing.expectEqualSlices(u8, if (kind == 0) args[8..16] else &expected, try session.bytes(&value));
                            break;
                        },
                        else => return error.UnexpectedOutcome,
                    }
                }
            }
        };
    }
}
