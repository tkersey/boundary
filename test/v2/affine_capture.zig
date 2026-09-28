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

pub fn recurrentFixture() ir.Program {
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

test "source-free closed link runs affine synthesis and preserves recurrent observations" {
    const a = std.testing.allocator;
    const original = comptime recurrentFixture();
    const object: data.component.Object = .{
        .program = original,
        .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }},
        .borrows = &.{.{ .function = 0 }},
    };
    const bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(bytes);
    _ = try data.component.encode(a, object, bytes);
    const Trace = struct {
        affine_seen: bool = false,
        fn enter(context: *anyopaque, stage: data.closed_compilation.Stage) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (stage == .affine_state) self.affine_seen = true;
        }
    };
    var trace: Trace = .{};
    var stats: data.closed_compilation.Statistics = .{};
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "object", .object = bytes }}, &.{}, .{ .instance = "object", .symbol = "main" }, .{
        .contract = .semantic,
        .statistics = &stats,
        .observer = .{ .context = &trace, .enter = Trace.enter },
    });
    defer linked.deinit();
    @memset(bytes, 0xff);
    try std.testing.expect(trace.affine_seen);
    try std.testing.expectEqual(data.closed_compilation.Outcome.applied, stats.outcome);
    const output = try a.alloc(u8, try image.encodedLength(linked.program));
    defer a.free(output);
    _ = try linked.encode(a, output);
    const words = [_]u64{ 1, 2, 4, 8 };
    for ([_]u8{ 0, 2, 8, 31 }) |count| {
        var state = words[0..3].*;
        for (0..count) |_| {
            const p0 = state[0];
            const q0 = state[1];
            const r0 = state[2];
            state[0] = q0;
            state[1] = r0;
            state[2] = p0 ^ words[3] ^ 0xa5;
        }
        var args: [33]u8 = undefined;
        for (words, 0..) |word, i| std.mem.writeInt(u64, args[i * 8 ..][0..8], word, .little);
        args[32] = count;
        var expected: [8]u8 = undefined;
        std.mem.writeInt(u64, &expected, state[0] ^ state[1] ^ words[3] ^ 0xa5, .little);
        var outcome = try world.invocation.invoke(a, .{ .image = output, .instance = .{ .initial_args = &args } });
        defer outcome.deinit();
        try std.testing.expect(outcome.record == .completed);
        try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
    }
}

fn twoModes() ir.Program {
    var program = fixture;
    program.constants = &.{ fixture.constants[0], .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } } };
    program.blocks = &.{
        fixture.blocks[0],                                                                                                                                                                                                                                                           fixture.blocks[1], fixture.blocks[2],
        .{ .function = 1, .instructions = &.{
            .{ .destination = 5, .opcode = .constant, .immediate = 1 },
            .{ .destination = 6, .opcode = .equal, .operands = &.{ 3, 5 } },
        }, .terminator = .{ .branch = .{ .condition = 6, .when_true = .{ .block = 6 }, .when_false = .{ .block = 7 } } } },
        fixture.blocks[4],                                                                                                                                                                                                                                                           fixture.blocks[5], fixture.blocks[3],
        .{ .function = 1, .instructions = &.{.{ .destination = 6, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 1, 0, 2, 3, 6 }, .next = .{ .block = 4, .assignments = &.{.{ .destination = 7, .source = .returned }} } } } },
    };
    return program;
}

test "World preserves both dynamically selected affine update modes" {
    const a = std.testing.allocator;
    const original = comptime twoModes();
    var candidate = try affine.run(a, original, 0, null, 100000, .{});
    defer candidate.deinit();
    for ([_]u64{ 0, 9, std.math.maxInt(u64) }) |input| {
        var args: [33]u8 = undefined;
        for ([_]u64{ 1, 2, 4, input }, 0..) |word, i| std.mem.writeInt(u64, args[i * 8 ..][0..8], word, .little);
        args[32] = 1;
        var expected: [8]u8 = undefined;
        std.mem.writeInt(u64, &expected, if (input == 0) 2 ^ 4 else 1 ^ 2, .little);
        for ([_]ir.Program{ original, candidate.program }) |program| {
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

pub fn parityFixture(allocator: std.mem.Allocator, n: usize) !ir.Program {
    std.debug.assert(n >= 2 and n <= 128);
    const inputs = try allocator.alloc(u64, n + 2);
    for (inputs, 0..) |*slot, i| slot.* = i;
    const fields = try allocator.alloc(u64, n);
    @memset(fields, 0);
    const captures = try allocator.alloc(u64, n);
    for (captures, 0..) |*slot, i| slot.* = i;
    const main_layout = try allocator.alloc(u64, n + 4);
    @memset(main_layout, 0);
    main_layout[n + 1] = 2;
    main_layout[n + 2] = 3;
    const worker_layout = try allocator.alloc(u64, n + 5);
    @memset(worker_layout, 0);
    worker_layout[n + 1] = 2;
    worker_layout[n + 3] = 2;
    const call_args = try allocator.alloc(u64, n + 2);
    for (call_args[0..n], 0..) |*slot, i| {
        const permutation = (i * (if (n == 3) @as(usize, 2) else 5) + 1) % n;
        slot.* = if (permutation == 0) n + 2 else permutation;
    }
    call_args[n] = n;
    call_args[n + 1] = n + 3;
    const observations = try allocator.alloc(ir.Instruction, n - 1);
    for (observations, 0..) |*op, i| op.* = .{ .destination = n + 2, .opcode = .integer_bit_xor, .operands = try allocator.dupe(u64, &.{ if (i == 0) 0 else n + 2, i + 1 }) };
    var program = fixture;
    program.functions = try allocator.dupe(ir.Function, &.{
        .{ .entry = 0, .inputs = inputs, .layout = .{ .slots = main_layout }, .result = 0 },
        .{ .entry = 2, .inputs = inputs, .layout = .{ .slots = worker_layout }, .result = 0 },
    });
    program.scopes.captures = try allocator.dupe(data.program.Capture, &.{.{ .fields = fields, .use = .reusable }});
    program.blocks = try allocator.dupe(ir.Block, &.{
        .{ .function = 0, .instructions = try allocator.dupe(ir.Instruction, &.{.{ .destination = n + 2, .opcode = .computation, .operands = captures }}), .terminator = .{ .apply = .{ .computation = n + 2, .arguments = try allocator.dupe(u64, &.{ n, n + 1 }), .next = .{ .block = 1, .assignments = try allocator.dupe(ir.Assignment, &.{.{ .destination = n + 3, .source = .returned }}) } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = n + 3 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = n + 1, .when_true = .{ .block = 3 }, .when_false = .{ .block = 5 } } } },
        .{ .function = 1, .instructions = try allocator.dupe(ir.Instruction, &.{
            .{ .destination = n + 2, .opcode = .integer_bit_xor, .operands = try allocator.dupe(u64, &.{ 0, n }) },
            .{ .destination = n + 3, .opcode = .constant, .immediate = 0 },
        }), .terminator = .{ .call = .{ .function = 1, .arguments = call_args, .next = .{ .block = 4, .assignments = try allocator.dupe(ir.Assignment, &.{.{ .destination = n + 4, .source = .returned }}) } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = n + 4 } },
        .{ .function = 1, .instructions = observations, .terminator = .{ .return_value = n + 2 } },
    });
    return program;
}

pub fn inspectionThenLoop(storage: std.mem.Allocator) !ir.Program {
    var program = try parityFixture(storage, 2);
    const schema = data.program.Schema;
    program.schemas = try storage.dupe(schema, &.{ program.schemas[0], program.schemas[1], program.schemas[2], program.schemas[3], .{ .product = &.{ 0, 0 } } });
    program.effects = &.{.{ .identity = "affine/full-inspection", .payload = 4, .result = 1, .external = true }};
    const functions = try storage.dupe(ir.Function, program.functions);
    functions[0].effects = &.{0};
    functions[0].layout.slots = &.{ 0, 0, 0, 2, 3, 0, 4 };
    program.functions = functions;
    const blocks = try storage.alloc(ir.Block, 7);
    @memcpy(blocks[0..6], program.blocks);
    blocks[6] = program.blocks[0];
    blocks[0] = .{ .function = 0, .instructions = &.{.{ .destination = 6, .opcode = .product, .operands = &.{ 0, 1 } }}, .terminator = .{ .perform = .{ .effect = 0, .payload = 6, .next = .{ .block = 6 } } } };
    program.blocks = blocks;
    return program;
}

test "full inspection request resumes into compressed private loop" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try inspectionThenLoop(arena.allocator());
    var stats: affine.Statistics = .{};
    var reduced = try affine.run(a, original, 0, &stats, 1000000, .{});
    defer reduced.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.reduced_words);
    var args: [25]u8 = undefined;
    for ([_]u64{ 1, 2, 8 }, 0..) |value, i| std.mem.writeInt(u64, args[i * 8 ..][0..8], value, .little);
    args[24] = 1;
    for ([_]ir.Program{ original, reduced.program }) |program| {
        const bytes = try a.alloc(u8, try image.encodedLength(program));
        defer a.free(bytes);
        _ = try image.encode(a, program, bytes);
        var pending = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
        defer pending.deinit();
        try std.testing.expect(pending.record == .requested);
        var request = try data.invocation.decode(data.invocation.Request, a, pending.record.requested.request);
        defer request.deinit();
        try std.testing.expectEqualSlices(u8, "affine/full-inspection", request.value.binding.semantic_identity);
        try std.testing.expectEqualSlices(u8, args[0..16], request.value.binding.payload);
        const response = try data.invocation.encodeOwned(data.invocation.Result, a, .{ .request_identity = request.value.request_identity, .value = &.{} });
        defer a.free(response);
        var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = pending.record.requested.state.? }, .control = .{ .reply = response } });
        defer outcome.deinit();
        try std.testing.expect(outcome.record == .completed);
        var expected: [8]u8 = undefined;
        std.mem.writeInt(u64, &expected, 1 ^ 2 ^ 8, .little);
        try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
    }
}

const cyclic: ir.Program = .{
    .roots = fixture.roots,
    .schemas = fixture.schemas,
    .constants = fixture.constants,
    .effects = fixture.effects,
    .functions = fixture.functions,
    .scopes = fixture.scopes,
    .constructors = fixture.constructors,
    .blocks = &.{
        fixture.blocks[0],                                                                                                                                       fixture.blocks[1],
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 4, .when_true = .{ .block = 3 }, .when_false = .{ .block = 4 } } } },
        .{ .function = 1, .instructions = fixture.blocks[3].instructions, .terminator = .{ .jump = .{ .block = 2, .assignments = &.{
            .{ .destination = 0, .source = .{ .slot = 1 } },
            .{ .destination = 1, .source = .{ .slot = 2 } },
            .{ .destination = 2, .source = .{ .slot = 5 } },
            .{ .destination = 4, .source = .{ .slot = 6 } },
        } } } },
        fixture.blocks[5],
    },
};

test "World preserves reduced parallel capture back edges" {
    const a = std.testing.allocator;
    var stats: data.closed_compilation.Statistics = .{};
    var optimized = try data.closed_compilation.run(a, cyclic, .{ .contract = .semantic, .statistics = &stats });
    defer optimized.deinit();
    try std.testing.expectEqual(data.closed_compilation.Outcome.applied, stats.outcome);
    for ([_]bool{ false, true }) |rotate| {
        var args: [33]u8 = undefined;
        for ([_]u64{ 1, 2, 4, 8 }, 0..) |value, i| std.mem.writeInt(u64, args[i * 8 ..][0..8], value, .little);
        args[32] = @intFromBool(rotate);
        var expected: [8]u8 = undefined;
        std.mem.writeInt(u64, &expected, if (rotate) 2 ^ 4 else 1 ^ 2, .little);
        for ([_]ir.Program{ cyclic, optimized.program }) |program| {
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

test "independent objects expose imported recursive capture worker only at closed link" {
    const a = std.testing.allocator;
    const original = comptime recurrentFixture();
    var caller_program = original;
    caller_program.functions = &.{ original.functions[0], .{ .entry = data.relocation.missing, .inputs = &.{ 0, 1, 2, 3, 4 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 4 } }, .result = 0 } };
    caller_program.blocks = original.blocks[0..2];
    const caller: data.component.Object = .{
        .program = caller_program,
        .imports = &.{.{ .name = "worker", .reference = .{ .kind = .function, .id = 1 } }},
        .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }},
        .borrows = &.{ .{ .function = 0 }, .{ .function = 1 } },
    };
    var worker_program = original;
    worker_program.roots.entry = 0;
    var worker_function = original.functions[1];
    worker_function.entry = 0;
    worker_program.functions = &.{worker_function};
    var blocks = original.blocks[2..6].*;
    for (&blocks) |*block| {
        block.function = 0;
        switch (block.terminator) {
            .branch => |*branch| {
                branch.when_true.block -= 2;
                branch.when_false.block -= 2;
            },
            .call => |*call| {
                call.function = 0;
                call.next.block -= 2;
            },
            else => {},
        }
    }
    worker_program.blocks = &blocks;
    worker_program.constructors = &.{};
    worker_program.scopes.captures = &.{};
    const worker: data.component.Object = .{
        .program = worker_program,
        .exports = &.{.{ .name = "worker", .reference = .{ .kind = .function, .id = 0 } }},
        .borrows = &.{.{ .function = 0 }},
    };
    const caller_bytes = try a.alloc(u8, try data.component.encodedLength(caller));
    defer a.free(caller_bytes);
    const worker_bytes = try a.alloc(u8, try data.component.encodedLength(worker));
    defer a.free(worker_bytes);
    _ = try data.component.encode(a, caller, caller_bytes);
    _ = try data.component.encode(a, worker, worker_bytes);
    const bindings = &.{data.linker.Binding{ .required = .{ .instance = "caller", .symbol = "worker" }, .supplied = .{ .instance = "worker", .symbol = "worker" } }};
    const instances = &.{ data.linker.Instance{ .key = "caller", .object = caller_bytes }, data.linker.Instance{ .key = "worker", .object = worker_bytes } };
    var structural = try data.linker.link(a, instances, bindings, .{ .instance = "caller", .symbol = "main" });
    defer structural.deinit();
    var stats: data.closed_compilation.Statistics = .{};
    var semantic = try data.linker.linkWithCompilation(a, instances, bindings, .{ .instance = "caller", .symbol = "main" }, .{ .contract = .semantic, .statistics = &stats });
    defer semantic.deinit();
    try std.testing.expectEqual(data.closed_compilation.Outcome.applied, stats.outcome);
    // The standalone affine pass confirms this is an actual capture-state
    // opportunity, independently of other reductions chosen by the pipeline.
    var affine_stats: affine.Statistics = .{};
    var affine_only = try affine.run(a, structural.program, 0, &affine_stats, 1000000, .{});
    defer affine_only.deinit();
    try std.testing.expectEqual(@as(usize, 2), affine_stats.reduced_words);
    @memset(caller_bytes, 0xff);
    @memset(worker_bytes, 0xff);
    var args: [33]u8 = undefined;
    for ([_]u64{ 1, 2, 4, 8 }, 0..) |value, i| std.mem.writeInt(u64, args[i * 8 ..][0..8], value, .little);
    args[32] = 2;
    var expected: [8]u8 = undefined;
    // Two rotations: (1,2,4) -> (2,4,172) -> (4,172,175).
    std.mem.writeInt(u64, &expected, 4 ^ 172 ^ 8 ^ 0xa5, .little);
    for ([_]ir.Program{ structural.program, semantic.program, affine_only.program }) |program| {
        const bytes = try a.alloc(u8, try image.encodedLength(program));
        defer a.free(bytes);
        _ = try image.encode(a, program, bytes);
        var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
        defer outcome.deinit();
        try std.testing.expect(outcome.record == .completed);
        try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
    }
}

test "private affine input normalization rejects a missing caller conversion" {
    const a = std.testing.allocator;
    const original = comptime recurrentFixture();
    var candidate = (try data.affine_candidate.construct(a, original, 0, 1000000)).?;
    defer candidate.deinit();
    try std.testing.expectEqual(@as(u64, 0xa5), candidate.input_bias[0]);
    try affine.validate(a, original, candidate.program, 0, candidate.basis, candidate.input_bias, 1000000);
    var altered = candidate.program;
    const blocks = try a.dupe(ir.Block, altered.blocks);
    defer a.free(blocks);
    const arguments = try a.dupe(u64, blocks[0].terminator.apply.arguments);
    defer a.free(arguments);
    arguments[0] = 3;
    blocks[0].terminator.apply.arguments = arguments;
    altered.blocks = blocks;
    var admitted = try data.activation_ownership.analyze(a, altered);
    defer admitted.deinit();
    try std.testing.expectError(error.InvalidAffineCandidate, affine.validate(a, original, altered, 0, candidate.basis, candidate.input_bias, 1000000));
}
