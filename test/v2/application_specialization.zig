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

fn argumentBranchProgram(comptime known: bool) ir.Program {
    var program = comptime closedBranchProgram(false);
    program.roots = .{ .entry = 3, .result = 3, .failure = 1 };
    program.functions = &.{ program.functions[0], program.functions[1], program.functions[2], .{ .entry = 7, .inputs = if (known) &.{ 0, 1 } else &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 4, 3 } }, .result = 3 } };
    program.blocks = &.{
        program.blocks[0],                                                                                                                                                                                                                                                                          program.blocks[1],                                                              program.blocks[2], program.blocks[3], program.blocks[4], program.blocks[5], program.blocks[6],
        .{ .function = 3, .instructions = if (known) &.{.{ .destination = 2, .opcode = .constant, .immediate = 0 }} else &.{}, .terminator = .{ .call = .{ .function = 0, .arguments = &.{ 0, 1, 2 }, .next = .{ .block = 8, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } }, .{ .function = 3, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
    };
    return program;
}

fn incomingCallableProgram(comptime closed: bool) ir.Program {
    var program = captured;
    program.functions = &.{ captured.functions[0], if (closed) .{ .entry = 2, .inputs = &.{1}, .layout = .{ .slots = &.{ 0, 0, 3 } }, .result = 3 } else captured.functions[1], .{ .entry = 3, .inputs = &.{ 2, 1 }, .layout = captured.functions[0].layout, .result = 3 } };
    program.schemas = if (closed) &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 3, .use = .reusable } } }, .{ .product = &.{ 0, 0 } } } else captured.schemas;
    program.scopes = if (closed) .{ .captures = &.{.{ .fields = &.{}, .use = .reusable }} } else captured.scopes;
    program.blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .computation, .operands = if (closed) &.{} else &.{0}, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 2, .arguments = &.{ 2, 1 }, .next = captured.blocks[0].terminator.apply.next } } },
        captured.blocks[1],
        if (closed) .{ .function = 1, .instructions = &.{.{ .destination = 2, .opcode = .product, .operands = &.{ 1, 1 } }}, .terminator = .{ .return_value = 2 } } else captured.blocks[2],
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 2, .arguments = &.{1}, .next = .{ .block = 4, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
    };
    return program;
}

test "World preserves the known caller argument and incoming callable specializations" {
    const a = std.testing.allocator;
    for ([_]ir.Program{ comptime argumentBranchProgram(true), comptime incomingCallableProgram(true) }) |original| {
        var pruned = try data.branch_reduction.run(a, original, null, .{});
        defer pruned.deinit();
        var specialized = try data.application_specialization.run(a, pruned.program, null, .{});
        defer specialized.deinit();
        var fewer_arguments = try data.dead_arguments.run(a, specialized.program, null, .{});
        defer fewer_arguments.deinit();
        var optimized = try data.dead_computation.run(a, fewer_arguments.program, null, .{});
        defer optimized.deinit();
        for ([_]u64{ 0, 21, 999 }) |argument| {
            var args: [16]u8 = undefined;
            std.mem.writeInt(u64, args[0..8], 10, .little);
            std.mem.writeInt(u64, args[8..16], argument, .little);
            var expected: [16]u8 = undefined;
            std.mem.writeInt(u64, expected[0..8], argument, .little);
            std.mem.writeInt(u64, expected[8..16], argument, .little);
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
}

const private_arguments: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 1 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
    },
};

test "removing a private argument retains its faulting evaluation" {
    const a = std.testing.allocator;
    var original = private_arguments;
    original.constants = &.{.{ .schema = 1, .bytes = &.{} }};
    var blocks = private_arguments.blocks[0..3].*;
    blocks[0].instructions = &.{.{ .destination = 0, .opcode = .integer_div, .operands = &.{ 0, 1 }, .failures = &.{ .{ .kind = .arithmetic_overflow, .value = 0 }, .{ .kind = .division_by_zero, .value = 0 } } }};
    original.blocks = &blocks;
    var stats: data.dead_arguments.Statistics = .{};
    var fewer = try data.dead_arguments.run(a, original, &stats, .{});
    defer fewer.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.call_arguments_removed);
    var optimized = try data.dead_computation.run(a, fewer.program, null, .{});
    defer optimized.deinit();
    for ([_]ir.Program{ original, optimized.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{ 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } } });
        defer outcome.deinit();
        try std.testing.expect(outcome.record == .failed);
        try std.testing.expectEqualSlices(u8, &.{}, outcome.record.failed.value);
    }
}

test "independently linked caller and worker specialize without any source module" {
    const a = std.testing.allocator;
    const worker: data.component.Object = .{
        .program = comptime closedBranchProgram(false),
        .exports = &.{.{ .name = "worker", .reference = .{ .kind = .function, .id = 0 } }},
        .borrows = &.{.{ .function = 0 }},
    };
    const caller: data.component.Object = .{
        .program = .{
            .roots = .{ .entry = 0, .result = 3, .failure = 1 },
            .schemas = &.{ .u64, .unit, .boolean, .{ .product = &.{ 0, 0 } } },
            .constants = &.{.{ .schema = 2, .bytes = &.{1} }},
            .effects = &.{},
            .functions = &.{
                .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 2, 3 } }, .result = 3 },
                .{ .entry = data.relocation.missing, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 2 } }, .result = 3 },
            },
            .blocks = &.{
                .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 1, 2 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
                .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
            },
        },
        .imports = &.{.{ .name = "worker", .reference = .{ .kind = .function, .id = 1 } }},
        .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }},
        .borrows = &.{ .{ .function = 0 }, .{ .function = 1 } },
    };
    const worker_bytes = try a.alloc(u8, try data.component.encodedLength(worker));
    defer a.free(worker_bytes);
    const caller_bytes = try a.alloc(u8, try data.component.encodedLength(caller));
    defer a.free(caller_bytes);
    _ = try data.component.encode(a, worker, worker_bytes);
    _ = try data.component.encode(a, caller, caller_bytes);
    var linked = try data.linker.link(a, &.{ .{ .key = "caller", .object = caller_bytes }, .{ .key = "worker", .object = worker_bytes } }, &.{.{ .required = .{ .instance = "caller", .symbol = "worker" }, .supplied = .{ .instance = "worker", .symbol = "worker" } }}, .{ .instance = "caller", .symbol = "main" });
    defer linked.deinit();
    var pipeline_stats: data.closed_compilation.Statistics = .{};
    var integrated = try data.linker.linkWithCompilation(a, &.{ .{ .key = "caller", .object = caller_bytes }, .{ .key = "worker", .object = worker_bytes } }, &.{.{ .required = .{ .instance = "caller", .symbol = "worker" }, .supplied = .{ .instance = "worker", .symbol = "worker" } }}, .{ .instance = "caller", .symbol = "main" }, .{ .contract = .semantic, .statistics = &pipeline_stats });
    defer integrated.deinit();
    try std.testing.expectEqual(data.closed_compilation.Outcome.applied, pipeline_stats.outcome);
    @memset(caller_bytes, 0xff);
    @memset(worker_bytes, 0xff);
    var branch_stats: data.branch_reduction.Statistics = .{};
    var reduced = try data.branch_reduction.run(a, linked.program, &branch_stats, .{});
    defer reduced.deinit();
    try std.testing.expectEqual(@as(usize, 1), branch_stats.branches_removed);
    var call_stats: data.application_specialization.Statistics = .{};
    var specialized = try data.application_specialization.run(a, reduced.program, &call_stats, .{});
    defer specialized.deinit();
    try std.testing.expectEqual(@as(usize, 1), call_stats.direct_applications);
    var fewer = try data.dead_arguments.run(a, specialized.program, null, .{});
    defer fewer.deinit();
    var p01: data.coalescing.Statistics = .{};
    var optimized = try data.dead_computation.run(a, fewer.program, null, .{ .coalescing = .{ .statistics = &p01 } });
    defer optimized.deinit();
    try std.testing.expect(p01.outcome != .not_run);
    for (optimized.program.blocks) |block| {
        try std.testing.expect(block.terminator != .branch and block.terminator != .apply);
    }
    for ([_]ir.Program{ linked.program, optimized.program, integrated.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{ 10, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0 } } });
        defer outcome.deinit();
        try std.testing.expect(outcome.record == .completed);
        try std.testing.expectEqualSlices(u8, &.{ 21, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0 }, outcome.record.completed);
    }
    std.debug.print("two-object known-argument optimization: {d} -> {d} bytes\n", .{ try data.program_image.encodedLength(linked.program), try data.program_image.encodedLength(optimized.program) });
}

fn maskedBranch(comptime opcode: data.program.Opcode) ir.Program {
    return .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit, .boolean },
        .constants = &.{
            .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } },
            .{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } },
        },
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0, 0, 0, 2 } }, .result = 0 }},
        .blocks = &.{
            .{ .function = 0, .instructions = &.{
                .{ .destination = 1, .opcode = .constant, .immediate = 0 },
                .{ .destination = 2, .opcode = .constant, .immediate = 1 },
                .{ .destination = 3, .opcode = .integer_bit_and, .operands = &.{ 0, 1 } },
                .{ .destination = 4, .opcode = opcode, .operands = &.{ 3, 2 } },
            }, .terminator = .{ .branch = .{ .condition = 4, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
        },
    };
}

test "source-free integer branch proof preserves extreme unsigned inputs" {
    const a = std.testing.allocator;
    const original = comptime maskedBranch(.less);
    const object: data.component.Object = .{
        .program = original,
        .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }},
        .borrows = &.{.{ .function = 0 }},
    };
    const object_bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(object_bytes);
    _ = try data.component.encode(a, object, object_bytes);
    var stats: data.closed_compilation.Statistics = .{};
    var p01: data.coalescing.Statistics = .{};
    var optimized = try data.linker.linkWithCompilation(a, &.{.{ .key = "integer", .object = object_bytes }}, &.{}, .{ .instance = "integer", .symbol = "main" }, .{ .contract = .semantic, .statistics = &stats, .coalescing = .{ .statistics = &p01 } });
    defer optimized.deinit();
    @memset(object_bytes, 0xff);
    try std.testing.expectEqual(data.closed_compilation.Outcome.applied, stats.outcome);
    try std.testing.expect(p01.outcome != .not_run);
    for (optimized.program.blocks) |block| try std.testing.expect(block.terminator != .branch);
    for ([_]u64{ 0, 1, 0x8000000000000000, std.math.maxInt(u64) }) |input| {
        var args: [8]u8 = undefined;
        std.mem.writeInt(u64, &args, input, .little);
        for ([_]ir.Program{ original, optimized.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer outcome.deinit();
            try std.testing.expect(outcome.record == .completed);
            try std.testing.expectEqualSlices(u8, &args, outcome.record.completed);
        }
    }
    std.debug.print("integer branch source-free: {d} -> {d} bytes\n", .{ try data.program_image.encodedLength(original), try data.program_image.encodedLength(optimized.program) });
}

test "proved integer branch retains an earlier failing computation" {
    const a = std.testing.allocator;
    const baseline = comptime maskedBranch(.less);
    var original = baseline;
    original.constants = &.{ baseline.constants[0], baseline.constants[1], .{ .schema = 1, .bytes = &.{} } };
    var blocks = baseline.blocks[0..3].*;
    blocks[0].instructions = &.{
        baseline.blocks[0].instructions[0],
        baseline.blocks[0].instructions[1],
        .{ .destination = 3, .opcode = .integer_div, .operands = &.{ 0, 1 }, .failures = &.{ .{ .kind = .arithmetic_overflow, .value = 2 }, .{ .kind = .division_by_zero, .value = 2 } } },
        baseline.blocks[0].instructions[2],
        baseline.blocks[0].instructions[3],
    };
    original.blocks = &blocks;
    var stats: data.branch_reduction.Statistics = .{};
    var reduced = try data.branch_reduction.run(a, original, &stats, .{});
    defer reduced.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.branches_removed);
    var optimized = try data.dead_computation.run(a, reduced.program, null, .{});
    defer optimized.deinit();
    for ([_]ir.Program{ original, optimized.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{ 42, 0, 0, 0, 0, 0, 0, 0 } } });
        defer outcome.deinit();
        try std.testing.expect(outcome.record == .failed);
        try std.testing.expectEqualSlices(u8, &.{}, outcome.record.failed.value);
    }
}

fn variantBranch(comptime known: bool) ir.Program {
    return .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit, .boolean, .{ .sum = &.{ 0, 0 } } },
        .effects = &.{},
        .constants = &.{.{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } }},
        .functions = &.{.{ .entry = 0, .inputs = if (known) &.{0} else &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 3, 0, 0, 2 } }, .result = 0 }},
        .blocks = &.{
            .{ .function = 0, .instructions = if (known) &.{
                .{ .destination = 1, .opcode = .variant, .operands = &.{0}, .immediate = 1 },
                .{ .destination = 2, .opcode = .variant_tag, .operands = &.{1} },
                .{ .destination = 3, .opcode = .constant, .immediate = 0 },
                .{ .destination = 4, .opcode = .equal, .operands = &.{ 2, 3 } },
            } else &.{
                .{ .destination = 2, .opcode = .variant_tag, .operands = &.{1} },
                .{ .destination = 3, .opcode = .constant, .immediate = 0 },
                .{ .destination = 4, .opcode = .equal, .operands = &.{ 2, 3 } },
            }, .terminator = .{ .branch = .{ .condition = 4, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        },
    };
}

test "source-free variant facts remove a branch without inspecting the runtime payload" {
    const a = std.testing.allocator;
    inline for (.{ true, false }) |known| {
        const original = comptime variantBranch(known);
        const object: data.component.Object = .{
            .program = original,
            .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }},
            .borrows = &.{.{ .function = 0 }},
        };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var p01: data.coalescing.Statistics = .{};
        var selected = try data.linker.linkWithCompilation(a, &.{.{ .key = "variant", .object = encoded }}, &.{}, .{ .instance = "variant", .symbol = "main" }, .{ .contract = .semantic, .coalescing = .{ .statistics = &p01 } });
        defer selected.deinit();
        @memset(encoded, 0xff);
        try std.testing.expect(p01.outcome != .not_run);
        var branches: usize = 0;
        for (selected.program.blocks) |block| {
            if (block.terminator == .branch) branches += 1;
        }
        try std.testing.expectEqual(@as(usize, if (known) 0 else 1), branches);
        for ([_]u64{ 0, 42, std.math.maxInt(u64) }) |input| {
            for ([_]u8{ 0, 1 }) |tag| {
                var args: [17]u8 = undefined;
                std.mem.writeInt(u64, args[0..8], input, .little);
                args[8] = tag;
                std.mem.writeInt(u64, args[9..17], 123, .little);
                var expected: [8]u8 = undefined;
                std.mem.writeInt(u64, &expected, if (known or tag == 1) input else 1, .little);
                for ([_]ir.Program{ original, selected.program }) |program| {
                    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                    defer a.free(bytes);
                    _ = try data.program_image.encode(a, program, bytes);
                    var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = args[0..if (known) 8 else 17] } });
                    defer outcome.deinit();
                    try std.testing.expect(outcome.record == .completed);
                    try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
                }
            }
        }
        if (known) std.debug.print("variant branch source-free: {d} -> {d} bytes\n", .{ try data.program_image.encodedLength(original), try data.program_image.encodedLength(selected.program) });
    }
}

fn productFieldBranch(comptime field: u64) ir.Program {
    const base = comptime closedBranchProgram(true);
    return .{
        .roots = base.roots,
        .schemas = &.{ base.schemas[0], base.schemas[1], base.schemas[2], base.schemas[3], base.schemas[4], .{ .product = &.{ 4, 4 } } },
        .constants = &.{ base.constants[0], base.constants[1], .{ .schema = 4, .bytes = &.{0} } },
        .effects = base.effects,
        .functions = &.{
            .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 2, 3, 4, 5, 4 } }, .result = 3 },
            base.functions[1],
            base.functions[2],
        },
        .blocks = &.{
            .{ .function = 0, .instructions = &.{
                .{ .destination = 4, .opcode = .constant, .immediate = 0 },
                .{ .destination = 6, .opcode = .constant, .immediate = 2 },
                .{ .destination = 5, .opcode = .product, .operands = &.{ 4, 6 } },
                .{ .destination = 4, .opcode = .field, .operands = &.{5}, .immediate = field },
            }, .terminator = base.blocks[0].terminator },
            base.blocks[1],
            base.blocks[2],
            base.blocks[3],
            base.blocks[4],
            base.blocks[5],
            base.blocks[6],
        },
        .scopes = base.scopes,
        .constructors = base.constructors,
    };
}

test "checked product field feeds facts branch pruning and direct calls through source-free linking" {
    const a = std.testing.allocator;
    inline for (.{ @as(u64, 0), @as(u64, 1) }) |field| {
        const original = comptime productFieldBranch(field);
        const object: data.component.Object = .{
            .program = original,
            .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }},
            .borrows = &.{.{ .function = 0 }},
        };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var stats: data.closed_compilation.Statistics = .{};
        var p01: data.coalescing.Statistics = .{};
        var optimized = try data.linker.linkWithCompilation(a, &.{.{ .key = "product", .object = encoded }}, &.{}, .{ .instance = "product", .symbol = "main" }, .{ .contract = .semantic, .statistics = &stats, .coalescing = .{ .statistics = &p01 } });
        defer optimized.deinit();
        @memset(encoded, 0xff);
        try std.testing.expectEqual(data.closed_compilation.Outcome.applied, stats.outcome);
        try std.testing.expect(stats.rounds >= 2);
        try std.testing.expect(p01.outcome != .not_run);
        var calls: usize = 0;
        for (optimized.program.blocks) |block| {
            try std.testing.expect(block.terminator != .branch and block.terminator != .apply);
            if (block.terminator == .call) calls += 1;
            for (block.instructions) |op| try std.testing.expect(op.opcode != .field and op.opcode != .computation);
        }
        try std.testing.expectEqual(@as(usize, 1), calls);
        const args = [_]u8{ 10, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0 };
        const expected = [_]u8{ if (field == 0) 21 else 99, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0 };
        for ([_]ir.Program{ original, optimized.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer outcome.deinit();
            try std.testing.expect(outcome.record == .completed);
            try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
        }
        std.debug.print("product-field/branch/direct-call field {d}: {d} -> {d} bytes\n", .{ field, try data.program_image.encodedLength(original), try data.program_image.encodedLength(optimized.program) });
    }
}

pub const interaction: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{0}, .use = .linear } } }, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{ 0, 0 }, .use = .linear } } }, .boolean },
    .constants = &.{.{ .schema = 4, .bytes = &.{1} }},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 2, 3, 0 } }, .result = 0 },
        .{ .entry = 3, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 4, 0, 0 } }, .result = 0 },
        .{ .entry = 6, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0, 4, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .computation, .operands = &.{0}, .immediate = 0 }}, .terminator = .{ .apply = .{ .computation = 4, .arguments = &.{3}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 6, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 5, .opcode = .computation, .operands = &.{ 1, 2 }, .immediate = 1 }}, .terminator = .{ .apply = .{ .computation = 5, .arguments = &.{3}, .next = .{ .block = 2, .assignments = &.{.{ .destination = 6, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 6 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 2, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 4 }, .when_false = .{ .block = 5 } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 2, .instructions = &.{.{ .destination = 3, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .branch = .{ .condition = 3, .when_true = .{ .block = 7 }, .when_false = .{ .block = 8 } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
        .{ .function = 2, .instructions = &.{.{ .destination = 4, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 4 } },
    },
    .scopes = .{ .captures = &.{ .{ .fields = &.{0}, .use = .linear }, .{ .fields = &.{ 0, 0 }, .use = .linear } } },
    .constructors = &.{ .{ .function = 1, .capture = 0, .schema = 2 }, .{ .function = 2, .capture = 1, .schema = 3 } },
};

test "G41 branch specialization dead capture arguments and coalescing have separate contributions" {
    const a = std.testing.allocator;
    const original = interaction;
    var branches: data.branch_reduction.Statistics = .{};
    var pruned = try data.branch_reduction.run(a, original, &branches, .{});
    defer pruned.deinit();
    try std.testing.expectEqual(@as(usize, 2), branches.branches_removed);
    var direct_stats: data.application_specialization.Statistics = .{};
    var direct = try data.application_specialization.run(a, pruned.program, &direct_stats, .{});
    defer direct.deinit();
    try std.testing.expectEqual(@as(usize, 2), direct_stats.direct_applications);
    try std.testing.expectEqual(@as(usize, 3), direct.program.functions.len);
    var removed: data.dead_arguments.Statistics = .{};
    var p01: data.coalescing.Statistics = .{};
    var selected = try data.dead_arguments.run(a, direct.program, &removed, .{ .statistics = &p01 });
    defer selected.deinit();
    try std.testing.expectEqual(@as(usize, 3), removed.parameters_removed);
    try std.testing.expectEqual(@as(usize, 3), removed.call_arguments_removed);
    const function_kind = @backingInt(data.relocation.Kind.function);
    // The admitted pre-P01 candidate still has three declarations. Mandatory
    // P01 then shares the two workers whose formerly captured inputs disappeared.
    try std.testing.expectEqual(@as(usize, 3), p01.baseline.catalogs[function_kind]);
    try std.testing.expectEqual(@as(usize, 2), selected.program.functions.len);

    var without_branch = try data.application_specialization.run(a, original, null, .{});
    defer without_branch.deinit();
    var branch_ablation = try data.dead_arguments.run(a, without_branch.program, &removed, .{});
    defer branch_ablation.deinit();
    try std.testing.expectEqual(@as(usize, 0), removed.parameters_removed);
    var call_ablation = try data.dead_arguments.run(a, pruned.program, &removed, .{});
    defer call_ablation.deinit();
    try std.testing.expectEqual(@as(usize, 0), removed.parameters_removed);
    try std.testing.expectEqual(@as(usize, 2), call_ablation.program.constructors.len);
    var argument_ablation = try data.coalescing.run(a, direct.program, .{});
    defer argument_ablation.deinit();
    try std.testing.expectEqual(@as(usize, 3), argument_ablation.program.functions.len);

    var combined = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer combined.deinit();
    for ([_][4]u64{ .{ 7, 11, 13, 42 }, .{ 0, 1, 2, std.math.maxInt(u64) }, .{ 99, 98, 97, 0 } }) |words| {
        var args: [32]u8 = undefined;
        for (words, 0..) |word, i| std.mem.writeInt(u64, args[i * 8 ..][0..8], word, .little);
        for ([_]ir.Program{ original, selected.program, branch_ablation.program, call_ablation.program, argument_ablation.program, combined.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer outcome.deinit();
            try std.testing.expect(outcome.record == .completed);
            try std.testing.expectEqual(words[3], std.mem.readInt(u64, outcome.record.completed[0..8], .little));
        }
    }
}

pub const predecessor_transfer: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit },
    .constants = &.{.{ .schema = 0, .bytes = &.{ 7, 0, 0, 0, 0, 0, 0, 0 } }},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 }},
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 1, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .yield_value = .{ .block = 2, .assignments = &.{.{ .destination = 2, .source = .{ .slot = 1 } }} } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
    },
};

test "World executes retained transfer reads across predecessor blocks and closed linking" {
    const a = std.testing.allocator;
    var direct = try data.dead_computation.run(a, predecessor_transfer, null, .{});
    defer direct.deinit();
    var compiled = try data.closed_compilation.run(a, predecessor_transfer, .{ .contract = .semantic });
    defer compiled.deinit();
    const object: data.component.Object = .{ .program = predecessor_transfer, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "transfer", .object = encoded }}, &.{}, .{ .instance = "transfer", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(encoded, 0xff);
    for ([_]u64{ 0, 42, std.math.maxInt(u64) }) |word| {
        var args: [8]u8 = undefined;
        std.mem.writeInt(u64, &args, word, .little);
        for ([_]ir.Program{ predecessor_transfer, direct.program, compiled.program, linked.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args }, .quantum = 1 });
            defer result.deinit();
            var yields: usize = 0;
            var steps: usize = 0;
            while (result.record == .progressed or result.record == .yielded) {
                try std.testing.expect(steps < 16);
                const yielded = result.record == .yielded;
                yields += @intFromBool(yielded);
                const state = if (yielded) result.record.yielded.? else result.record.progressed.?;
                const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = state }, .control = if (yielded) .resume_yield else .none, .quantum = 1 });
                result.deinit();
                result = next;
                steps += 1;
            }
            try std.testing.expectEqual(@as(usize, 1), yields);
            try std.testing.expect(result.record == .completed);
            try std.testing.expectEqualSlices(u8, &args, result.record.completed);
        }
    }
}
