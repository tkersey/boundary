const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;

test "packed temporary reuse isolates an actually retained prior activation view" {
    const original: ir.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit },
        .constants = &.{},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0, 0, 0 } }, .result = 0 }},
        .blocks = &.{.{ .function = 0, .instructions = &.{
            .{ .destination = 1, .opcode = .integer_bit_not, .operands = &.{0} },
            .{ .destination = 2, .opcode = .integer_bit_not, .operands = &.{1} },
            .{ .destination = 3, .opcode = .integer_bit_not, .operands = &.{2} },
        }, .terminator = .{ .return_value = 3 } }},
    };
    var candidate = (try data.slot_packing.construct(a, original, .{})).?;
    defer candidate.deinit();
    try data.slot_packing.validate(a, original, candidate.program, candidate.maps, .{});
    const map = candidate.maps[0].?;
    try std.testing.expectEqual(map[1], map[2]);
    try std.testing.expectEqual(map[2], map[3]);
    const image = try a.alloc(u8, try data.program_image.encodedLength(candidate.program));
    defer a.free(image);
    _ = try data.program_image.encode(a, candidate.program, image);
    var session = try world.Session.initImage(a, image, &.{ 7, 0, 0, 0, 0, 0, 0, 0 });
    defer session.deinit();
    try session.step();
    const first = try session.frames.get(session.roots.current.?.id);
    const retained = try session.frames.forkFrame(first);
    defer session.frames.releaseFrame(retained);
    const prior = try session.frames.slots.get(retained.view, @intCast(map[1]));
    try std.testing.expectEqual(~@as(u64, 7), std.mem.readInt(u64, &prior.body.scalar, .little));
    const pages = session.frames.slots.statistics.live_pages;
    try session.step();
    const next = try session.frames.get(session.roots.current.?.id);
    const current = try session.frames.slots.get(next.view, @intCast(map[2]));
    try std.testing.expectEqual(@as(u64, 7), std.mem.readInt(u64, &current.body.scalar, .little));
    try std.testing.expectEqualDeep(prior, try session.frames.slots.get(retained.view, @intCast(map[1])));
    // An overwrite-only successor needs no predecessor descriptor copy.
    // The retained view still requires independent backing for the new value.
    try std.testing.expectEqual(pages + 1, session.frames.slots.statistics.live_pages);
    const checkpoint = try session.checkpoint(a);
    defer a.free(checkpoint);
    var restored = try world.Session.restoreImage(a, image, checkpoint);
    defer restored.deinit();
    const result = try restored.run(null);
    try std.testing.expect(result == .completed);
    try std.testing.expectEqual(~@as(u64, 7), std.mem.readInt(u64, (try restored.bytes(&result.completed))[0..8], .little));
}
pub const threshold: ir.Program = blk: {
    var slots: [66]u64 = @splat(0);
    slots[2] = 1;
    slots[65] = 2;
    const frozen = slots;
    break :blk .{
        .roots = .{ .entry = 0, .result = 2, .failure = 0 },
        .schemas = &.{ .u64, .boolean, .{ .product = &.{ 0, 0 } } },
        .constants = &.{},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &frozen }, .result = 2 }},
        .blocks = &.{
            .{ .function = 0, .instructions = &.{ .{ .destination = 63, .opcode = .integer_bit_not, .operands = &.{0} }, .{ .destination = 64, .opcode = .integer_bit_not, .operands = &.{1} } }, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 1, .assignments = &.{ .{ .destination = 0, .source = .{ .slot = 64 } }, .{ .destination = 1, .source = .{ .slot = 63 } } } }, .when_false = .{ .block = 1, .assignments = &.{ .{ .destination = 0, .source = .{ .slot = 63 } }, .{ .destination = 1, .source = .{ .slot = 64 } } } } } } },
            .{ .function = 0, .instructions = &.{.{ .destination = 65, .opcode = .product, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 65 } },
        },
    };
};
test "World preserves packed swaps and checkpoint values through closed linking" {
    var packed_program = try data.slot_packing.run(a, threshold, null, .{});
    defer packed_program.deinit();
    var compiled = try data.closed_compilation.run(a, threshold, .{ .contract = .semantic });
    defer compiled.deinit();
    const object: data.component.Object = .{ .program = threshold, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "packed", .object = encoded }}, &.{}, .{ .instance = "packed", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(encoded, 0xff);
    for ([_][2]u64{ .{ 0, 1 }, .{ 7, 11 }, .{ std.math.maxInt(u64), 0 } }) |words| for ([_]bool{ false, true }) |swap| {
        var args: [17]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], words[0], .little);
        std.mem.writeInt(u64, args[8..16], words[1], .little);
        args[16] = @intFromBool(swap);
        var expected: [16]u8 = undefined;
        std.mem.writeInt(u64, expected[0..8], ~words[@intFromBool(swap)], .little);
        std.mem.writeInt(u64, expected[8..16], ~words[@intFromBool(!swap)], .little);
        var baseline_steps: usize = 0;
        for ([_]ir.Program{ threshold, packed_program.program, compiled.program, linked.program }, 0..) |program, arm| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args }, .quantum = 1 });
            defer result.deinit();
            var steps: usize = 1;
            while (result.record == .progressed) {
                try std.testing.expect(steps < 20);
                const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = result.record.progressed.? }, .quantum = 1 });
                result.deinit();
                result = next;
                steps += 1;
            }
            try std.testing.expect(result.record == .completed);
            try std.testing.expectEqualSlices(u8, &expected, result.record.completed);
            if (arm == 0) baseline_steps = steps else try std.testing.expectEqual(baseline_steps, steps);
        }
    };
}

test "packing preserves values when saving and restoring midway through a loop" {
    const original: ir.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 0 },
        .schemas = &.{ .u64, .boolean },
        .constants = &.{},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 1, 0, 1, 0, 0 } }, .result = 0 }},
        .blocks = &.{
            .{ .function = 0, .instructions = &.{ .{ .destination = 2, .opcode = .integer_bit_not, .operands = &.{0} }, .{ .destination = 4, .opcode = .integer_bit_not, .operands = &.{2} }, .{ .destination = 5, .opcode = .integer_bit_not, .operands = &.{4} } }, .terminator = .{ .jump = .{ .block = 1, .assignments = &.{.{ .destination = 0, .source = .{ .slot = 5 } }} } } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 1, .when_true = .{ .block = 2 }, .when_false = .{ .block = 3 } } } },
            .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .boolean_not, .operands = &.{1} }}, .terminator = .{ .jump = .{ .block = 0, .assignments = &.{.{ .destination = 1, .source = .{ .slot = 3 } }} } } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        },
    };
    var compact = try data.slot_packing.run(a, original, null, .{});
    defer compact.deinit();
    try std.testing.expect(compact.program.functions[0].layout.slots.len < original.functions[0].layout.slots.len);
    for ([_]u64{ 0, 7, std.math.maxInt(u64) }) |word| for ([_]bool{ false, true }) |again| {
        var args: [9]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], word, .little);
        args[8] = @intFromBool(again);
        var expected_steps: usize = 0;
        for ([_]ir.Program{ original, compact.program }, 0..) |program, arm| {
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
            try std.testing.expectEqual(if (again) word else ~word, std.mem.readInt(u64, result.record.completed[0..8], .little));
            if (arm == 0) expected_steps = steps else try std.testing.expectEqual(expected_steps, steps);
        }
    };
}
