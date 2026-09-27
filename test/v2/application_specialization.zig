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

fn branchProgram(comptime known: bool) ir.Program {
    return .{
        .roots = captured.roots,
        .schemas = &.{ captured.schemas[0], captured.schemas[1], captured.schemas[2], captured.schemas[3], .boolean },
        .constants = &.{.{ .schema = 4, .bytes = &.{1} }},
        .effects = &.{},
        .functions = &.{
            .{ .entry = 0, .inputs = if (known) &.{ 0, 1 } else &.{ 0, 1, 4 }, .layout = .{ .slots = &.{ 0, 0, 2, 3, 4 } }, .result = 3 },
            .{ .entry = 5, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 3 } }, .result = 3 },
            .{ .entry = 6, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 3 } }, .result = 3 },
        },
        .blocks = &.{
            .{ .function = 0, .instructions = if (known) &.{.{ .destination = 4, .opcode = .constant, .immediate = 0 }} else &.{}, .terminator = .{ .branch = .{ .condition = 4, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
            .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .computation, .operands = &.{0}, .immediate = 0 }}, .terminator = .{ .jump = .{ .block = 3 } } },
            .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .computation, .operands = &.{1}, .immediate = 1 }}, .terminator = .{ .jump = .{ .block = 3 } } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 2, .arguments = &.{1}, .next = .{ .block = 4, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
            .{ .function = 1, .instructions = captured.blocks[2].instructions, .terminator = captured.blocks[2].terminator },
            .{ .function = 2, .instructions = &.{.{ .destination = 2, .opcode = .product, .operands = &.{ 1, 0 } }}, .terminator = .{ .return_value = 2 } },
        },
        .scopes = captured.scopes,
        .constructors = &.{ captured.constructors[0], .{ .function = 2, .capture = 0, .schema = 2 } },
    };
}

fn closedBranchProgram(comptime known: bool) ir.Program {
    var program = comptime branchProgram(known);
    program.schemas = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 3, .use = .reusable } } }, .{ .product = &.{ 0, 0 } }, .boolean };
    program.constants = &.{ .{ .schema = 4, .bytes = &.{1} }, .{ .schema = 0, .bytes = &.{ 99, 0, 0, 0, 0, 0, 0, 0 } } };
    program.functions = &.{ program.functions[0], .{ .entry = 5, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0, 3 } }, .result = 3 }, .{ .entry = 6, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0, 3 } }, .result = 3 } };
    program.blocks = &.{
        program.blocks[0],
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .computation, .immediate = 0 }}, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .computation, .immediate = 1 }}, .terminator = .{ .jump = .{ .block = 3 } } },
        program.blocks[3],
        program.blocks[4],
        .{ .function = 1, .instructions = &.{.{ .destination = 2, .opcode = .product, .operands = &.{ 0, 0 } }}, .terminator = .{ .return_value = 2 } },
        .{ .function = 2, .instructions = &.{ .{ .destination = 1, .opcode = .constant, .immediate = 1 }, .{ .destination = 2, .opcode = .product, .operands = &.{ 1, 0 } } }, .terminator = .{ .return_value = 2 } },
    };
    program.scopes = .{ .captures = &.{.{ .fields = &.{}, .use = .reusable }} };
    return program;
}

test "World preserves the known-branch direct-call result and unknown alternatives" {
    const a = std.testing.allocator;
    const original = comptime closedBranchProgram(true);
    var reduced = try data.branch_reduction.run(a, original, null, .{});
    defer reduced.deinit();
    var optimized = try data.application_specialization.run(a, reduced.program, null, .{});
    defer optimized.deinit();
    var args: [16]u8 = undefined;
    std.mem.writeInt(u64, args[0..8], 10, .little);
    std.mem.writeInt(u64, args[8..16], 21, .little);
    var expected: [16]u8 = undefined;
    std.mem.writeInt(u64, expected[0..8], 21, .little);
    std.mem.writeInt(u64, expected[8..16], 21, .little);
    var eliminated = try data.dead_computation.run(a, optimized.program, null, .{});
    defer eliminated.deinit();
    for ([_]ir.Program{ original, optimized.program, eliminated.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
        defer outcome.deinit();
        try std.testing.expect(outcome.record == .completed);
        try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
    }
}

test "both externally selected constructor alternatives execute without specialization" {
    const a = std.testing.allocator;
    const original = comptime closedBranchProgram(false);
    var reduced = try data.branch_reduction.run(a, original, null, .{});
    defer reduced.deinit();
    var optimized = try data.application_specialization.run(a, reduced.program, null, .{});
    defer optimized.deinit();
    for ([_]u8{ 0, 1 }) |condition| {
        var args: [17]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], 10, .little);
        std.mem.writeInt(u64, args[8..16], 21, .little);
        args[16] = condition;
        var expected: [16]u8 = undefined;
        std.mem.writeInt(u64, expected[0..8], if (condition == 1) 21 else 99, .little);
        std.mem.writeInt(u64, expected[8..16], 21, .little);
        for ([_]ir.Program{ original, optimized.program }) |program| {
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

test "World still observes unused division failure after dead computation reduction" {
    const a = std.testing.allocator;
    const original: ir.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit },
        .constants = &.{.{ .schema = 1, .bytes = &.{} }},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0 }},
        .blocks = &.{.{ .function = 0, .instructions = &.{.{ .destination = 1, .opcode = .integer_div, .operands = &.{ 0, 0 }, .failures = &.{ .{ .kind = .arithmetic_overflow, .value = 0 }, .{ .kind = .division_by_zero, .value = 0 } } }}, .terminator = .{ .return_value = 0 } }},
    };
    var result = try data.dead_computation.run(a, original, null, .{});
    defer result.deinit();
    for ([_]ir.Program{ original, result.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } } });
        defer outcome.deinit();
        try std.testing.expect(outcome.record == .failed);
        try std.testing.expectEqualSlices(u8, &.{}, outcome.record.failed.value);
    }
}
