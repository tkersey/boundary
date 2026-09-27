const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const reused: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{0}, .use = .reusable } } }, .boolean },
    .constants = &.{.{ .schema = 3, .bytes = &.{1} }},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0, 2, 0 } }, .result = 0 },
        .{ .entry = 3, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 3 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .computation, .operands = &.{0}, .immediate = 0 }}, .terminator = .{ .apply = .{ .computation = 3, .arguments = &.{1}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 3, .arguments = &.{2}, .next = .{ .block = 2, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{0}, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 2 }},
};

test "source-free dead capture reduces retained environment and checkpoint payload" {
    const a = std.testing.allocator;
    var original = reused;
    original.schemas = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{5}, .use = .reusable } } }, .boolean, .u8, .{ .array = .{ .element = 4, .length = 4096 } } };
    original.functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 5, 0, 0, 2, 0 } }, .result = 0 },
        .{ .entry = 3, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 5, 0, 3 } }, .result = 0 },
    };
    original.scopes.captures = &.{.{ .fields = &.{5}, .use = .reusable }};
    const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
    const object_bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(object_bytes);
    _ = try data.component.encode(a, object, object_bytes);
    var linked = try data.linker.link(a, &.{.{ .key = "closure", .object = object_bytes }}, &.{}, .{ .instance = "closure", .symbol = "main" });
    defer linked.deinit();
    @memset(object_bytes, 0xff);
    var stats: data.capture_reduction.Statistics = .{};
    var reduced = try data.capture_reduction.run(a, linked.program, &stats, .{});
    defer reduced.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.fields_removed);
    var args: [4112]u8 = @splat(0xa5);
    std.mem.writeInt(u64, args[4096..4104], 21, .little);
    std.mem.writeInt(u64, args[4104..4112], 99, .little);
    var checkpoint_bytes: [2]usize = undefined;
    var blob_bytes: [2]usize = @splat(0);
    var captured_values: [2]usize = @splat(0);
    for ([_]ir.Program{ linked.program, reduced.program }, 0..) |program, index| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var paused = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args }, .quantum = 1 });
        defer paused.deinit();
        try std.testing.expect(paused.record == .progressed and paused.record.progressed != null);
        const checkpoint = paused.record.progressed.?;
        checkpoint_bytes[index] = checkpoint.len;
        var graph = try data.state_image.decodeGraph(a, checkpoint);
        defer graph.deinit();
        for (graph.state.blobs) |blob| blob_bytes[index] += blob.bytes.len;
        for (graph.state.nodes) |node| if (node.record == .computation) {
            const env = graph.state.nodes[@intCast(node.record.computation.environment.id)].record.environment;
            captured_values[index] += env.values.len;
        };
        // Resume each checkpoint against its own exact image identity.
        var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = checkpoint } });
        defer outcome.deinit();
        try std.testing.expect(outcome.record == .completed);
        try std.testing.expectEqualSlices(u8, &.{ 99, 0, 0, 0, 0, 0, 0, 0 }, outcome.record.completed);
    }
    try std.testing.expectEqual(@as(usize, 1), captured_values[0]);
    try std.testing.expectEqual(@as(usize, 0), captured_values[1]);
    try std.testing.expect(blob_bytes[0] >= 4096);
    try std.testing.expectEqual(@as(usize, 0), blob_bytes[1]);
    try std.testing.expect(checkpoint_bytes[1] < checkpoint_bytes[0]);
    std.debug.print("dead-capture retention: captured values {d}->{d}; reachable blob bytes {d}->{d}; checkpoint bytes {d}->{d}\n", .{ captured_values[0], captured_values[1], blob_bytes[0], blob_bytes[1], checkpoint_bytes[0], checkpoint_bytes[1] });
}

test "reused closure accepts distinct arguments after capture removal" {
    const a = std.testing.allocator;
    var original = reused;
    original.schemas = &.{ reused.schemas[0], reused.schemas[1], reused.schemas[2], reused.schemas[3], .{ .product = &.{ 0, 0 } } };
    original.roots.result = 4;
    original.functions = &.{ .{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0, 2, 0, 0, 4 } }, .result = 4 }, reused.functions[1] };
    original.blocks = &.{
        reused.blocks[0],
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 3, .arguments = &.{2}, .next = .{ .block = 2, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 6, .opcode = .product, .operands = &.{ 4, 5 } }}, .terminator = .{ .return_value = 6 } },
        reused.blocks[3],
    };
    var result = try data.capture_reduction.run(a, original, null, .{});
    defer result.deinit();
    for ([_][3]u64{ .{ 100, 21, 99 }, .{ 0, 999, 42 }, .{ 17, 42, 0 } }) |values| {
        var args: [24]u8 = undefined;
        for (values, 0..) |value, index| std.mem.writeInt(u64, args[index * 8 ..][0..8], value, .little);
        var expected: [16]u8 = undefined;
        std.mem.writeInt(u64, expected[0..8], values[1], .little);
        std.mem.writeInt(u64, expected[8..16], values[2], .little);
        for ([_]ir.Program{ original, result.program }) |program| {
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
