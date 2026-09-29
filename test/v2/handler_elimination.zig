const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;
pub const identity: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{}, .result = 0, .capture_bound = &.{0} } } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 2, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
        .{ .entry = 3, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{ .{ .destination = 1, .opcode = .integer_bit_not, .operands = &.{1} }, .{ .destination = 2, .opcode = .computation, .operands = &.{0} } }, .terminator = .{ .handle = .{ .handler = 0, .body = 2, .arguments = &.{}, .state = &.{1}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
    },
    .handlers = &.{.{ .mode = .deep, .input = 0, .answer = 0, .return_function = 2, .state = &.{0}, .clauses = &.{} }},
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 2 }},
    .scopes = .{ .captures = &.{.{ .fields = &.{0}, .use = .reusable }} },
};

test "empty identity handler elimination preserves results through source-free linking" {
    var structural = try data.closed_compilation.run(a, identity, .{});
    defer structural.deinit();
    var selected = try data.handler_elimination.run(a, identity, null, .{});
    defer selected.deinit();
    var compiled = try data.closed_compilation.run(a, identity, .{ .contract = .semantic });
    defer compiled.deinit();
    const object: data.component.Object = .{ .program = identity, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 } } };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "empty-handler", .object = encoded }}, &.{}, .{ .instance = "empty-handler", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(encoded, 0xff);
    try std.testing.expectEqual(@as(usize, 0), compiled.program.handlers.len);
    try std.testing.expectEqual(@as(usize, 0), linked.program.handlers.len);
    for ([_][2]u64{ .{ 0, 0 }, .{ 7, 11 }, .{ std.math.maxInt(u64), 42 } }) |values| {
        var args: [16]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], values[0], .little);
        std.mem.writeInt(u64, args[8..16], values[1], .little);
        var expected: [8]u8 = undefined;
        std.mem.writeInt(u64, &expected, values[0], .little);
        var baseline_steps: usize = 0;
        for ([_]ir.Program{ structural.program, selected.program, compiled.program, linked.program }, 0..) |program, arm| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args }, .quantum = 1 });
            defer result.deinit();
            var steps: usize = 1;
            while (result.record == .progressed) {
                try std.testing.expect(steps < 32);
                const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = result.record.progressed.? }, .quantum = 1 });
                result.deinit();
                result = next;
                steps += 1;
            }
            try std.testing.expect(result.record == .completed);
            try std.testing.expectEqualSlices(u8, &expected, result.record.completed);
            if (arm == 0) baseline_steps = steps else try std.testing.expect(steps < baseline_steps);
            std.debug.print("empty-handler arm={d} bytes={d} steps={d}\n", .{ arm, bytes.len, steps });
        }
    }
}

pub fn composedReturns(allocator: std.mem.Allocator) !ir.Program {
    var program = identity;
    // Boolean inputs make the complete admitted state space finite.
    program.schemas = &.{ .boolean, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{}, .result = 0, .capture_bound = &.{0} } } } };
    const functions = try allocator.alloc(ir.Function, 5);
    @memcpy(functions[0..3], identity.functions);
    functions[0].inputs = &.{ 0, 1, 4 };
    functions[0].layout.slots = &.{ 0, 0, 2, 0, 0 };
    functions[1].inputs = &.{ 0, 1 };
    functions[1].layout.slots = &.{ 0, 0, 2, 0 };
    functions[2].layout.slots = &.{ 0, 0, 0, 0 };
    functions[3] = .{ .entry = 5, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 };
    functions[4] = .{ .entry = 6, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 };
    const blocks = try allocator.alloc(ir.Block, 7);
    @memcpy(blocks[0..4], identity.blocks);
    blocks[0].instructions = &.{.{ .destination = 2, .opcode = .computation, .operands = &.{ 0, 4 } }};
    blocks[2] = .{ .function = 1, .instructions = &.{.{ .destination = 2, .opcode = .computation, .operands = &.{0}, .immediate = 1 }}, .terminator = .{ .handle = .{ .handler = 1, .body = 2, .arguments = &.{}, .state = &.{1}, .next = .{ .block = 4, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } };
    blocks[3].instructions = &.{ .{ .destination = 2, .opcode = .boolean_not, .operands = &.{1} }, .{ .destination = 3, .opcode = .select, .operands = &.{ 0, 2, 1 } } };
    blocks[3].terminator = .{ .return_value = 3 };
    blocks[4] = .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 3 } };
    blocks[5] = .{ .function = 3, .instructions = &.{}, .terminator = .{ .return_value = 0 } };
    blocks[6] = .{ .function = 4, .instructions = &.{.{ .destination = 2, .opcode = .select, .operands = &.{ 0, 0, 1 } }}, .terminator = .{ .return_value = 2 } };
    program.functions = functions;
    program.blocks = blocks;
    program.handlers = &.{
        .{ .mode = .deep, .input = 0, .answer = 0, .return_function = 2, .state = &.{0}, .clauses = &.{} },
        .{ .mode = .deep, .input = 0, .answer = 0, .return_function = 4, .state = &.{0}, .clauses = &.{} },
    };
    program.constructors = &.{ .{ .function = 1, .capture = 0, .schema = 2 }, .{ .function = 3, .capture = 1, .schema = 2 } };
    program.scopes.captures = &.{ .{ .fields = &.{ 0, 0 }, .use = .reusable }, .{ .fields = &.{0}, .use = .reusable } };
    return program;
}

test "ordered pure return composition is preserved for every finite input state" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try composedReturns(arena.allocator());
    var raw = try data.handler_elimination.construct(a, original, .{});
    defer raw.deinit();
    try data.handler_elimination.validate(a, original, raw.program, 1_000_000);
    var wrong_order = raw.program;
    const wrong_blocks = try arena.allocator().dupe(ir.Block, raw.program.blocks);
    for (wrong_blocks[original.blocks.len..]) |*block| {
        const function = &block.terminator.call.function;
        function.* = if (function.* == 2) 4 else 2;
    }
    wrong_order.blocks = wrong_blocks;
    var admitted = try data.activation_ownership.analyze(a, wrong_order);
    admitted.deinit();
    try std.testing.expectError(error.InvalidHandlerElimination, data.handler_elimination.validate(a, original, wrong_order, 1_000_000));
    const wrong_bytes = try a.alloc(u8, try data.program_image.encodedLength(wrong_order));
    defer a.free(wrong_bytes);
    _ = try data.program_image.encode(a, wrong_order, wrong_bytes);
    var wrong_result = try world.invocation.invoke(a, .{ .image = wrong_bytes, .instance = .{ .initial_args = &.{ 0, 1, 1 } } });
    defer wrong_result.deinit();
    try std.testing.expect(wrong_result.record == .completed);
    try std.testing.expectEqualSlices(u8, &.{1}, wrong_result.record.completed); // Correct order yields 0.
    var stats: data.handler_elimination.Statistics = .{};
    var selected = try data.handler_elimination.run(a, original, &stats, .{});
    defer selected.deinit();
    try std.testing.expectEqual(@as(usize, 2), stats.installations_removed);
    try std.testing.expectEqual(@as(usize, 2), stats.return_calls_preserved);
    var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer compiled.deinit();
    const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 }, .{ .function = 3 }, .{ .function = 4 } } };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "returns", .object = encoded }}, &.{}, .{ .instance = "returns", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(encoded, 0xff);
    for (0..2) |value| for (0..2) |outer| for (0..2) |inner| {
        const args = [_]u8{ @intCast(value), @intCast(outer), @intCast(inner) };
        const expected = [_]u8{@intCast((value | inner) ^ outer)};
        for ([_]ir.Program{ original, selected.program, compiled.program, linked.program }) |program| {
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
