const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const patterns = data.call_patterns;
const a = std.testing.allocator;
pub const repeated: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 2 },
    .schemas = &.{ .u64, .boolean, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{0}, .use = .reusable } } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 0, 0, 1, 1, 3, 0 } }, .result = 0 },
        .{ .entry = 6, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 3, 0, 0, 0, 0, 0 } }, .result = 0 },
        .{ .entry = 9, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
        .{ .entry = 10, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .computation, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 4, 0, 1 }, .next = .{ .block = 5, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 3, .when_true = .{ .block = 3 }, .when_false = .{ .block = 4 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .computation, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 4, 0, 1 }, .next = .{ .block = 5, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .computation, .immediate = 1 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 4, 0, 1 }, .next = .{ .block = 5, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 5 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 0, .arguments = &.{1}, .next = .{ .block = 7, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 0, .arguments = &.{2}, .next = .{ .block = 8, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 5, .opcode = .integer_bit_or, .operands = &.{ 3, 4 } }}, .terminator = .{ .return_value = 5 } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 3, .instructions = &.{.{ .destination = 1, .opcode = .integer_bit_not, .operands = &.{0} }}, .terminator = .{ .return_value = 1 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
    .constructors = &.{ .{ .function = 2, .capture = 0, .schema = 3 }, .{ .function = 3, .capture = 0, .schema = 3 } },
};

test "World executes repeated callable workers through compilation and closed linking" {
    var direct = try patterns.run(a, repeated, null, .{});
    defer direct.deinit();
    var statistics: data.closed_compilation.Statistics = .{};
    var compiled = try data.closed_compilation.run(a, repeated, .{ .contract = .semantic, .statistics = &statistics });
    defer compiled.deinit();
    try std.testing.expectEqual(.full, statistics.selected_candidate);
    const object: data.component.Object = .{ .program = repeated, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 }, .{ .function = 3 } } };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "patterns", .object = encoded }}, &.{}, .{ .instance = "patterns", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(encoded, 0xff);
    for ([_][2]u64{ .{ 1, 2 }, .{ 7, 11 }, .{ std.math.maxInt(u64), std.math.maxInt(u64) } }) |words| for ([_]bool{ false, true }) |first| for ([_]bool{ false, true }) |second| {
        var args: [18]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], words[0], .little);
        std.mem.writeInt(u64, args[8..16], words[1], .little);
        args[16] = @intFromBool(first);
        args[17] = @intFromBool(second);
        const expected = if (first or second) words[0] | words[1] else (~words[0]) | (~words[1]);
        for ([_]ir.Program{ repeated, direct.program, compiled.program, linked.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer result.deinit();
            try std.testing.expect(result.record == .completed);
            try std.testing.expectEqual(expected, std.mem.readInt(u64, result.record.completed[0..8], .little));
        }
    };
}

test "a locally collected hot-path profile preserves held-out reachable alternatives" {
    var collector = try data.optimization_profile.Collector.init(a, repeated);
    defer collector.deinit();
    const original_bytes = try a.alloc(u8, try data.program_image.encodedLength(repeated));
    defer a.free(original_bytes);
    _ = try data.program_image.encode(a, repeated, original_bytes);
    var input = @as([18]u8, @splat(0));
    input[0] = 5;
    input[8] = 3;
    var training = try world.Session.initImage(a, original_bytes, &input);
    defer training.deinit();
    var steps: usize = 0;
    while (true) {
        try std.testing.expect(steps < 100);
        if (training.roots.current) |current| {
            const node = try training.store.get(current);
            if (node == .control and (try training.frames.get(current.id)).position == 0)
                try collector.observe(@intCast(node.control.block));
        }
        steps += 1;
        switch (try training.run(1)) {
            .progressed => {},
            .completed => break,
            else => return error.UnexpectedTrainingOutcome,
        }
    }
    var snapshot = try collector.snapshot(a);
    defer snapshot.deinit();
    try std.testing.expect(snapshot.record.block_counts[4] > 0);
    try std.testing.expectEqual(@as(u64, 0), snapshot.record.block_counts[1]);
    var statistics: patterns.Statistics = .{};
    var optimized = try patterns.run(a, repeated, &statistics, .{ .profile = snapshot.record, .max_variants = 1 });
    defer optimized.deinit();
    try std.testing.expectEqual(@as(usize, 1), statistics.variants);
    const policy: data.closed_compilation.ProfilePolicy = .{ .record = snapshot.record, .max_variants = 1 };
    var shared_stats: data.closed_compilation.Statistics = .{};
    var shared = try data.closed_compilation.run(a, repeated, .{ .contract = .semantic, .profile = policy, .statistics = &shared_stats });
    defer shared.deinit();
    try std.testing.expect(shared_stats.profile_used);
    try std.testing.expectEqual(@as(usize, 1), shared_stats.profile_variants);
    const object: data.component.Object = .{ .program = repeated, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 }, .{ .function = 3 } } };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "profile", .object = encoded }}, &.{}, .{ .instance = "profile", .symbol = "main" }, .{ .contract = .semantic, .profile = policy, .statistics = &shared_stats });
    defer linked.deinit();
    @memset(encoded, 0xff);
    try std.testing.expect(shared_stats.profile_used);
    try std.testing.expectEqual(@as(usize, 1), shared_stats.profile_variants);
    for ([_]ir.Program{ optimized.program, shared.program, linked.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        for ([_]bool{ false, true }) |first| for ([_]bool{ false, true }) |second| {
            input[16] = @intFromBool(first);
            input[17] = @intFromBool(second);
            const expected: u64 = if (first or second) 7 else (~@as(u64, 5)) | (~@as(u64, 3));
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &input } });
            defer result.deinit();
            try std.testing.expect(result.record == .completed);
            try std.testing.expectEqual(expected, std.mem.readInt(u64, result.record.completed[0..8], .little));
        };
    }
}

pub const leaf_product: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .product = &.{ 0, 0 } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 2, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{0}, .layout = .{ .slots = &.{ 2, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .product, .operands = &.{ 0, 1 } }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{2}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 1, .opcode = .field, .operands = &.{0}, .immediate = 1 }}, .terminator = .{ .return_value = 1 } },
    },
};

pub const leaf_overwrite: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{0}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 1, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 2 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 0, .opcode = .integer_bit_not, .operands = &.{0} }}, .terminator = .{ .return_value = 0 } },
    },
};

test "World preserves leaf substitution and product cancellation" {
    for ([_]ir.Program{ leaf_product, leaf_overwrite }, 0..) |original, fixture| {
        var candidate = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
        defer candidate.deinit();
        for ([_]u64{ 0, 1, 0xfedcba9876543210 }) |word| {
            var args: [16]u8 = undefined;
            std.mem.writeInt(u64, args[0..8], word, .little);
            std.mem.writeInt(u64, args[8..16], ~word, .little);
            const expected = if (fixture == 0) ~word else std.math.maxInt(u64);
            for ([_]ir.Program{ original, candidate.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = args[0..if (fixture == 0) @as(usize, 16) else 8] } });
                defer result.deinit();
                try std.testing.expect(result.record == .completed);
                try std.testing.expectEqual(expected, std.mem.readInt(u64, result.record.completed[0..8], .little));
            }
        }
    }
}

pub const tagged: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 2 },
    .schemas = &.{ .u64, .boolean, .unit, .{ .sum = &.{ 0, 0 } } },
    .constants = &.{.{ .schema = 2, .bytes = &.{} }},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 0, 0, 1, 1, 3, 0 } }, .result = 0 },
        .{ .entry = 6, .inputs = &.{0}, .layout = .{ .slots = &.{ 3, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .variant, .operands = &.{0}, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{4}, .next = .{ .block = 5, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 3, .when_true = .{ .block = 3 }, .when_false = .{ .block = 4 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .variant, .operands = &.{1}, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{4}, .next = .{ .block = 5, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .variant, .operands = &.{0}, .immediate = 1 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{4}, .next = .{ .block = 5, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 5 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 1, .opcode = .variant_payload, .operands = &.{0}, .immediate = 0, .failures = &.{.{ .kind = .invalid_variant, .value = 0 }} }}, .terminator = .{ .return_value = 1 } },
    },
};

test "World preserves variant payload specialization and failing fallback after source-free link" {
    for (0..4) |fixture| {
        var original = tagged;
        var blocks: [9]ir.Block = undefined;
        @memcpy(blocks[0..7], tagged.blocks);
        if (fixture == 1) blocks[4].instructions = tagged.blocks[1].instructions;
        if (fixture == 2) blocks[1].instructions = &.{ tagged.blocks[1].instructions[0], .{ .destination = 0, .opcode = .integer_bit_not, .operands = &.{0} } };
        if (fixture == 3) {
            blocks[6].instructions = &.{};
            blocks[6].terminator = .{ .switch_variant = .{ .value = 0, .cases = &.{
                .{ .block = 7, .assignments = &.{.{ .destination = 1, .source = .returned }} },
                .{ .block = 8, .assignments = &.{.{ .destination = 1, .source = .returned }} },
            } } };
            blocks[7] = .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 1 } };
            blocks[8] = blocks[7];
        }
        original.blocks = blocks[0..(if (fixture == 3) @as(usize, 9) else 7)];
        var pattern_stats: patterns.Statistics = .{};
        var checked = try patterns.run(a, original, &pattern_stats, .{});
        defer checked.deinit();
        if (fixture == 3) try std.testing.expect(pattern_stats.variant_switches > 0);
        var statistics: data.closed_compilation.Statistics = .{};
        var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic, .statistics = &statistics });
        defer compiled.deinit();
        if (fixture == 1) try std.testing.expectEqual(.full, statistics.selected_candidate);
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 } } };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "variants", .object = encoded }}, &.{}, .{ .instance = "variants", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        for ([_][2]u64{ .{ 0, 1 }, .{ 7, 11 }, .{ std.math.maxInt(u64), 0 } }) |words| for ([_]bool{ false, true }) |first| for ([_]bool{ false, true }) |second| {
            var args: [18]u8 = undefined;
            std.mem.writeInt(u64, args[0..8], words[0], .little);
            std.mem.writeInt(u64, args[8..16], words[1], .little);
            args[16] = @intFromBool(first);
            args[17] = @intFromBool(second);
            for ([_]ir.Program{ original, checked.program, compiled.program, linked.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
                defer result.deinit();
                if (fixture != 1 and fixture != 3 and !first and !second) {
                    try std.testing.expect(result.record == .failed);
                    try std.testing.expectEqualSlices(u8, &.{}, result.record.failed.value);
                } else {
                    try std.testing.expect(result.record == .completed);
                    try std.testing.expectEqual(if (first or !second) words[0] else words[1], std.mem.readInt(u64, result.record.completed[0..8], .little));
                }
            }
        };
    }
}

pub const choice: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 2 },
    .schemas = &.{ .u64, .boolean, .unit },
    .constants = &.{ .{ .schema = 1, .bytes = &.{1} }, .{ .schema = 1, .bytes = &.{0} } },
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 1, 1, 0 } }, .result = 0 },
        .{ .entry = 4, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 1, 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 3, 0, 1 }, .next = .{ .block = 3, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .constant, .immediate = 1 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 3, 0, 1 }, .next = .{ .block = 3, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 0, .when_true = .{ .block = 5 }, .when_false = .{ .block = 6 } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
    },
};

test "World executes proved Boolean workers and unknown fallback through closed linking" {
    for (0..2) |fixture| {
        var original = choice;
        var blocks = choice.blocks[0..7].*;
        var functions = choice.functions[0..2].*;
        if (fixture == 1) {
            functions[0].inputs = &.{ 0, 1, 2, 3 };
            blocks[1].instructions = &.{};
        }
        original.blocks = &blocks;
        original.functions = &functions;
        var checked = try patterns.run(a, original, null, .{});
        defer checked.deinit();
        var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
        defer compiled.deinit();
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 } } };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "constants", .object = encoded }}, &.{}, .{ .instance = "constants", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        for ([_][2]u64{ .{ 0, 1 }, .{ 7, 11 }, .{ std.math.maxInt(u64), 0 } }) |words| for ([_]bool{ false, true }) |branch| for ([_]bool{ false, true }) |unknown| {
            var args: [18]u8 = undefined;
            std.mem.writeInt(u64, args[0..8], words[0], .little);
            std.mem.writeInt(u64, args[8..16], words[1], .little);
            args[16] = @intFromBool(branch);
            args[17] = @intFromBool(unknown);
            const expected = if (branch and (fixture == 0 or unknown)) words[0] else words[1];
            for ([_]ir.Program{ original, checked.program, compiled.program, linked.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = args[0..if (fixture == 0) @as(usize, 17) else 18] } });
                defer result.deinit();
                try std.testing.expect(result.record == .completed);
                try std.testing.expectEqual(expected, std.mem.readInt(u64, result.record.completed[0..8], .little));
            }
        };
    }
}

pub const word_constants: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 2 },
    .schemas = &.{ .u64, .boolean, .unit },
    .constants = &.{ .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } } },
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 1, 0, 0 } }, .result = 0 },
        .{ .entry = 4, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0, 1 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 1, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 2 }, .next = .{ .block = 3, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .constant, .immediate = 1 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 2 }, .next = .{ .block = 3, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{ .{ .destination = 2, .opcode = .constant, .immediate = 0 }, .{ .destination = 3, .opcode = .equal, .operands = &.{ 1, 2 } } }, .terminator = .{ .branch = .{ .condition = 3, .when_true = .{ .block = 5 }, .when_false = .{ .block = 6 } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 2, .opcode = .integer_bit_not, .operands = &.{0} }}, .terminator = .{ .return_value = 2 } },
    },
};

test "World executes width-correct unsigned workers and preserves a preceding arithmetic fault" {
    for (0..5) |fixture| {
        const width: usize = if (fixture == 4) 8 else (@as(usize, 1) << @intCast(fixture));
        const schema: data.program.Schema = switch (width) {
            1 => .u8,
            2 => .u16,
            4 => .u32,
            else => .u64,
        };
        var original = word_constants;
        original.schemas = &.{ schema, .boolean, .unit };
        const literals = [_]data.program.Literal{ .{ .schema = 0, .bytes = word_constants.constants[0].bytes[0..width] }, .{ .schema = 0, .bytes = word_constants.constants[1].bytes[0..width] }, .{ .schema = 2, .bytes = &.{} } };
        original.constants = &literals;
        var blocks = word_constants.blocks[0..7].*;
        if (fixture == 4) blocks[4].instructions = &.{ .{ .destination = 0, .opcode = .integer_div, .operands = &.{ 0, 1 }, .failures = &.{ .{ .kind = .arithmetic_overflow, .value = 2 }, .{ .kind = .division_by_zero, .value = 2 } } }, word_constants.blocks[4].instructions[0], word_constants.blocks[4].instructions[1] };
        original.blocks = &blocks;
        var checked = try patterns.run(a, original, null, .{});
        defer checked.deinit();
        var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
        defer compiled.deinit();
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 } } };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "words", .object = encoded }}, &.{}, .{ .instance = "words", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        for ([_]u64{ 0, 1, std.math.maxInt(u64) }) |value| for ([_]bool{ false, true }) |first| {
            var args: [9]u8 = undefined;
            std.mem.writeInt(u64, args[0..8], value, .little);
            args[width] = @intFromBool(first);
            var expected: [8]u8 = undefined;
            std.mem.writeInt(u64, &expected, if (first) value else ~value, .little);
            for ([_]ir.Program{ original, checked.program, compiled.program, linked.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = args[0 .. width + 1] } });
                defer result.deinit();
                if (fixture == 4 and first) {
                    try std.testing.expect(result.record == .failed);
                    try std.testing.expectEqualSlices(u8, &.{}, result.record.failed.value);
                } else {
                    try std.testing.expect(result.record == .completed);
                    try std.testing.expectEqualSlices(u8, expected[0..width], result.record.completed);
                }
            }
        };
    }
}

pub const captured: ir.Program = blk: {
    var functions = repeated.functions[0..4].*;
    functions[2].inputs = &.{ 0, 1, 2 };
    functions[2].layout.slots = &.{ 0, 0, 0, 0, 0 };
    var blocks = repeated.blocks[0..11].*;
    blocks[1].instructions = &.{.{ .destination = 4, .opcode = .computation, .operands = &.{ 0, 1 }, .immediate = 0 }};
    blocks[3].instructions = &.{.{ .destination = 4, .opcode = .computation, .operands = &.{ 1, 0 }, .immediate = 0 }};
    blocks[9].instructions = &.{ .{ .destination = 3, .opcode = .integer_bit_xor, .operands = &.{ 0, 2 } }, .{ .destination = 4, .opcode = .integer_bit_and, .operands = &.{ 3, 1 } } };
    blocks[9].terminator.return_value = 4;
    const frozen_functions = functions;
    const frozen_blocks = blocks;
    var program = repeated;
    program.functions = &frozen_functions;
    program.blocks = &frozen_blocks;
    program.scopes.captures = &.{ repeated.scopes.captures[0], .{ .fields = &.{ 0, 0 }, .use = .reusable } };
    program.constructors = &.{ .{ .function = 2, .capture = 1, .schema = 3 }, repeated.constructors[1] };
    break :blk program;
};

test "World preserves runtime captures and original captured values after source-free linking" {
    for (0..2) |fixture| {
        var original = captured;
        var blocks = captured.blocks[0..11].*;
        if (fixture == 1) blocks[1].instructions = &.{ captured.blocks[1].instructions[0], .{ .destination = 0, .opcode = .integer_bit_not, .operands = &.{0} } };
        original.blocks = &blocks;
        var checked = try patterns.run(a, original, null, .{});
        defer checked.deinit();
        var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
        defer compiled.deinit();
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 }, .{ .function = 3 } } };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "captured", .object = encoded }}, &.{}, .{ .instance = "captured", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        for ([_][2]u64{ .{ 0, 1 }, .{ 7, 11 }, .{ std.math.maxInt(u64), 0 } }) |words| for ([_]bool{ false, true }) |first| for ([_]bool{ false, true }) |second| {
            var args: [18]u8 = undefined;
            std.mem.writeInt(u64, args[0..8], words[0], .little);
            std.mem.writeInt(u64, args[8..16], words[1], .little);
            args[16] = @intFromBool(first);
            args[17] = @intFromBool(second);
            const expected = if (first) (if (fixture == 1) words[1] else (~words[0]) & words[1]) else if (second) words[0] & (~words[1]) else (~words[0]) | (~words[1]);
            for ([_]ir.Program{ original, checked.program, compiled.program, linked.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
                defer result.deinit();
                try std.testing.expect(result.record == .completed);
                try std.testing.expectEqual(expected, std.mem.readInt(u64, result.record.completed[0..8], .little));
            }
        };
    }
}
