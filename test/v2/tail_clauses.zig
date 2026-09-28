const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;
pub const administrative: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{
        .u64,                                                                                                                 .unit,                                                                                                                                                       .boolean,
        .{ .internal = .{ .computation = .{ .parameters = &.{5}, .result = 0, .effects = &.{0}, .capture_bound = &.{0} } } }, .{ .internal = .{ .resumption = .{ .effect = 0, .input = 0, .answer = 0, .handled = &.{0}, .capture_bound = &.{ 0, 5 }, .mode = .deep, .use = .linear } } }, .{ .internal = .{ .capability = 0 } },
    },
    .constants = &.{},
    .effects = &.{.{ .identity = "test.tail.admin", .payload = 0, .result = 0, .external = false }},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 3, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 5, 0, 0 } }, .result = 0, .effects = &.{0} },
        .{ .entry = 4, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
        .{ .entry = 5, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 4, 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 1, .opcode = .computation, .operands = &.{0}, .immediate = 0 }}, .terminator = .{ .handle = .{ .handler = 0, .body = 1, .arguments = &.{}, .state = &.{}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .perform = .{ .effect = 0, .capability = 1, .payload = 0, .next = .{ .block = 3, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 3, .opcode = .integer_bit_not, .operands = &.{2} }}, .terminator = .{ .return_value = 3 } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 3, .instructions = &.{}, .terminator = .{ .resume_value = .{ .resumption = 1, .argument = 0, .next = .{ .block = 6, .assignments = &.{ .{ .destination = 2, .source = .returned }, .{ .destination = 3, .source = .{ .slot = 0 } } } } } } },
        .{ .function = 3, .instructions = &.{.{ .destination = 0, .opcode = .move, .operands = &.{2} }}, .terminator = .{ .jump = .{ .block = 7, .assignments = &.{ .{ .destination = 2, .source = .{ .slot = 0 } }, .{ .destination = 0, .source = .{ .slot = 3 } } } } } },
        .{ .function = 3, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
    },
    .handlers = &.{.{ .mode = .deep, .input = 0, .answer = 0, .return_function = 2, .clauses = &.{.{ .effect = 0, .function = 3, .resumption = 4 }} }},
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 3 }},
    .scopes = .{ .captures = &.{.{ .fields = &.{0}, .use = .reusable }} },
};

test "World executes checked administrative tail clauses through source-free linking" {
    var structural = try data.closed_compilation.run(a, administrative, .{});
    defer structural.deinit();
    var selected = try data.tail_clauses.run(a, administrative, null, .{});
    defer selected.deinit();
    var compiled = try data.closed_compilation.run(a, administrative, .{ .contract = .semantic });
    defer compiled.deinit();
    const object: data.component.Object = .{ .program = administrative, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 }, .{ .function = 3 } } };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "tail", .object = encoded }}, &.{}, .{ .instance = "tail", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(encoded, 0xff);
    try std.testing.expect(compiled.program.handlers[0].clauses[0].strategy == .tail);
    try std.testing.expect(linked.program.handlers[0].clauses[0].strategy == .tail);
    for ([_]u64{ 0, 7, std.math.maxInt(u64) }) |input| {
        var args: [8]u8 = undefined;
        var expected: [8]u8 = undefined;
        std.mem.writeInt(u64, &args, input, .little);
        std.mem.writeInt(u64, &expected, ~input, .little);
        var baseline_steps: usize = 0;
        for ([_]ir.Program{ administrative, structural.program, selected.program, compiled.program, linked.program }, 0..) |program, arm| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args }, .quantum = 1 });
            defer outcome.deinit();
            var steps: usize = 1;
            while (outcome.record == .progressed) {
                try std.testing.expect(steps < 64);
                const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = outcome.record.progressed.? }, .quantum = 1 });
                outcome.deinit();
                outcome = next;
                steps += 1;
            }
            try std.testing.expect(outcome.record == .completed);
            try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
            if (arm == 0) baseline_steps = steps else if (arm == 1) try std.testing.expectEqual(baseline_steps, steps) else try std.testing.expect(steps < baseline_steps);
            std.debug.print("tail input={d} arm={d} bytes={d} steps={d}\n", .{ input, arm, bytes.len, steps });
        }
    }
}

test "nested installations keep older-capability dispatch and non-tail answers" {
    const boundary = @import("boundary");
    var builder = boundary.source.Builder.init(a);
    defer builder.deinit();
    var original = try boundary.program.compile(a, try boundary.source.examples.nested(&builder));
    defer original.deinit();
    var stats: data.tail_clauses.Statistics = .{};
    var retained = try data.tail_clauses.run(a, original.program, &stats, .{});
    defer retained.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.clauses_selected);
    for (retained.program.handlers) |handler| for (handler.clauses) |clause|
        try std.testing.expect(clause.strategy == .general);
    for ([_]ir.Program{ original.program, retained.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{} }, .quantum = 1 });
        defer result.deinit();
        var steps: usize = 1;
        while (result.record == .progressed) {
            try std.testing.expect(steps < 128);
            const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = result.record.progressed.? }, .quantum = 1 });
            result.deinit();
            result = next;
            steps += 1;
        }
        try std.testing.expect(result.record == .completed);
        // Inner resume: (5 + 1) * 10 + 7; outer return then contributes *10 +7.
        var expected: [8]u8 = undefined;
        std.mem.writeInt(u64, &expected, 677, .little);
        try std.testing.expectEqualSlices(u8, &expected, result.record.completed);
    }
}

test "retained resumptions and suspending cleanup keep their exact images" {
    const boundary = @import("boundary");
    inline for (.{ boundary.source.examples.cloned, boundary.source.examples.yieldingCleanup }) |example| {
        var builder = boundary.source.Builder.init(a);
        defer builder.deinit();
        var original = try boundary.program.compile(a, try example(&builder));
        defer original.deinit();
        var stats: data.tail_clauses.Statistics = .{};
        var retained = try data.tail_clauses.run(a, original.program, &stats, .{});
        defer retained.deinit();
        try std.testing.expectEqual(@as(usize, 0), stats.clauses_selected);
        try std.testing.expect(!stats.work_limit);
        try std.testing.expectEqual(try data.program_image.identity(a, original.program), try data.program_image.identity(a, retained.program));
    }
}
