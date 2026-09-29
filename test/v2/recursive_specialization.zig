const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;
pub const countdown: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .boolean, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .use = .reusable } } } },
    .constants = &.{ .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 1, .bytes = &.{} } },
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 3, 0, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 3, 0, 0, 0, 0, 0, 2, 0, 0, 0 } }, .result = 0 },
        .{ .entry = 7, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{ .{ .destination = 2, .opcode = .computation, .immediate = 0 }, .{ .destination = 3, .opcode = .constant, .immediate = 0 } }, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 2, 0, 1, 3 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
        .{ .function = 1, .instructions = &.{ .{ .destination = 4, .opcode = .constant, .immediate = 0 }, .{ .destination = 5, .opcode = .constant, .immediate = 1 }, .{ .destination = 6, .opcode = .equal, .operands = &.{ 1, 4 } } }, .terminator = .{ .branch = .{ .condition = 6, .when_true = .{ .block = 3 }, .when_false = .{ .block = 4 } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
        .{ .function = 1, .instructions = &.{ .{ .destination = 7, .opcode = .integer_sub, .operands = &.{ 1, 5 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 2 }} }, .{ .destination = 8, .opcode = .integer_add, .operands = &.{ 3, 5 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 2 }} } }, .terminator = .{ .apply = .{ .computation = 0, .arguments = &.{2}, .next = .{ .block = 5, .assignments = &.{.{ .destination = 9, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 7, 9, 8 }, .next = .{ .block = 6, .assignments = &.{.{ .destination = 9, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 9 } },
        .{ .function = 2, .instructions = &.{.{ .destination = 1, .opcode = .integer_bit_not, .operands = &.{0} }}, .terminator = .{ .return_value = 1 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
    .constructors = &.{.{ .function = 2, .capture = 0, .schema = 3 }},
};
pub fn withOpaqueEffect(allocator: std.mem.Allocator) !ir.Program {
    var result = countdown;
    result.effects = &.{.{ .identity = "p29/opaque", .payload = 0, .result = 0 }};
    const functions = try allocator.dupe(ir.Function, countdown.functions);
    functions[0].effects = &.{0};
    functions[1].effects = &.{0};
    result.functions = functions;
    const blocks = try allocator.alloc(ir.Block, countdown.blocks.len + 1);
    @memcpy(blocks[0..countdown.blocks.len], countdown.blocks);
    blocks[4].terminator = .{ .perform = .{ .effect = 0, .payload = 2, .next = .{ .block = 8, .assignments = &.{.{ .destination = 9, .source = .returned }} } } };
    blocks[8] = .{ .function = 1, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 0, .arguments = &.{9}, .next = countdown.blocks[4].terminator.apply.next } } };
    result.blocks = blocks;
    return result;
}

fn linked(original: ir.Program) !data.linker.Linked {
    const borrows = try a.alloc(data.borrow_contract.Summary, original.functions.len);
    defer a.free(borrows);
    for (borrows, 0..) |*summary, id| summary.* = .{ .function = id };
    const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = borrows };
    const bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(bytes);
    _ = try data.component.encode(a, object, bytes);
    const result = try data.linker.linkWithCompilation(a, &.{.{ .key = "recursive", .object = bytes }}, &.{}, .{ .instance = "recursive", .symbol = "main" }, .{ .contract = .semantic });
    @memset(bytes, 0xff);
    return result;
}
fn execute(program: ir.Program, n: u64, seed: u64, effectful: bool) !void {
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
    defer a.free(bytes);
    _ = try data.program_image.encode(a, program, bytes);
    var args: [16]u8 = undefined;
    std.mem.writeInt(u64, args[0..8], n, .little);
    std.mem.writeInt(u64, args[8..16], seed, .little);
    var session = try world.Session.initImage(a, bytes, &args);
    defer session.deinit();
    var requests: usize = 0;
    var expected = seed;
    var steps: usize = 0;
    while (steps < 100000) {
        steps += 1;
        switch (try session.run(1)) {
            .progressed => {
                if (steps % 7 == 0) {
                    const saved = try session.checkpoint(a);
                    defer a.free(saved);
                    const restored = try world.Session.restoreImage(a, bytes, saved);
                    session.deinit();
                    session = restored;
                }
            },
            .requested => {
                try std.testing.expect(effectful and requests < n);
                var pending = try session.pendingRequest(a);
                defer pending.deinit();
                try std.testing.expectEqualStrings("p29/opaque", pending.request.binding.semantic_identity);
                try std.testing.expectEqual(expected, std.mem.readInt(u64, pending.request.binding.payload[0..8], .little));
                var value: [8]u8 = undefined;
                std.mem.writeInt(u64, &value, expected ^ 0x55, .little);
                const reply = try data.invocation.encodeOwned(data.invocation.Result, a, .{ .request_identity = pending.request.request_identity, .value = &value });
                defer a.free(reply);
                const saved = try session.checkpoint(a);
                defer a.free(saved);
                const restored = try world.Session.restoreImage(a, bytes, saved);
                session.deinit();
                session = restored;
                try session.answer(reply);
                expected = ~(expected ^ 0x55);
                requests += 1;
            },
            .completed => |value| {
                if (effectful) try std.testing.expectEqual(n, requests) else expected = if (n % 2 == 0) seed else ~seed;
                try std.testing.expectEqual(expected, std.mem.readInt(u64, (try session.bytes(&value))[0..8], .little));
                return;
            },
            else => return error.UnexpectedOutcome,
        }
    }
    return error.StepLimit;
}
test "finite recursive workers preserve data demand and residual effect traces across closed linking" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    for ([_]bool{ false, true }) |effectful| {
        const original = if (effectful) try withOpaqueEffect(arena.allocator()) else countdown;
        var stats: data.call_patterns.Statistics = .{};
        var direct = try data.call_patterns.run(a, original, &stats, .{});
        defer direct.deinit();
        try std.testing.expect(stats.folded_calls > 0 and stats.generalized_parameters > 0 and !stats.work_limit);
        var compilation: data.closed_compilation.Statistics = .{};
        var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic, .statistics = &compilation });
        defer shared.deinit();
        var final = try linked(original);
        defer final.deinit();
        std.debug.print("recursive effects={any}: outcome={any} bytes={d}->{d}\n", .{ effectful, compilation.outcome, try data.program_image.encodedLength(original), try data.program_image.encodedLength(shared.program) });
        for ([_]u64{ 0, 1, 2, 7, 32 }) |n| for ([_]ir.Program{ original, direct.program, shared.program, final.program }) |program| try execute(program, n, 0x12345678, effectful);
    }
}
test "a delayed divergent callback is not evaluated while specializing" {
    var original = countdown;
    var blocks = countdown.blocks[0..8].*;
    original.blocks = &blocks;
    blocks[7].instructions = &.{};
    blocks[7].terminator = .{ .jump = .{ .block = 7 } };
    var direct = try data.call_patterns.run(a, original, null, .{});
    defer direct.deinit();
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer shared.deinit();
    for ([_]ir.Program{ original, direct.program, shared.program }) |program| {
        try execute(program, 0, 73, false);
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var args = [_]u8{0} ** 16;
        args[0] = 1;
        args[8] = 73;
        var session = try world.Session.initImage(a, bytes, &args);
        defer session.deinit();
        try std.testing.expect(try session.run(128) == .progressed);
    }
}

test "recursive driving retains failure order before a known callback" {
    var original = countdown;
    original.roots.failure = 0;
    original.constants = &.{ countdown.constants[0], countdown.constants[1], .{ .schema = 0, .bytes = &.{ 11, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 22, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 255, 255, 255, 255, 255, 255, 255, 255 } } };
    var blocks = countdown.blocks[0..8].*;
    original.blocks = &blocks;
    var entry = countdown.blocks[0].instructions[0..2].*;
    entry[1].immediate = 4;
    blocks[0].instructions = &entry;
    blocks[7].instructions = &.{ .{ .destination = 1, .opcode = .constant, .immediate = 1 }, .{ .destination = 1, .opcode = .integer_add, .operands = &.{ 0, 1 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 3 }} } };
    var candidate = (try data.call_patterns.construct(a, original, .{})).?;
    defer candidate.deinit();
    try data.call_patterns.validate(a, original, candidate.program, candidate.variants, candidate.sites, 10_000_000);
    const changed = try a.dupe(ir.Block, candidate.program.blocks);
    defer a.free(changed);
    const first = candidate.variants[0].first_block;
    changed[first + 2].instructions = changed[first + 2].instructions[0..1];
    changed[first + 3].instructions = &.{countdown.blocks[4].instructions[1]};
    var wrong = candidate.program;
    wrong.blocks = changed;
    var admitted = try data.activation_ownership.analyze(a, wrong);
    admitted.deinit();
    try std.testing.expectError(error.InvalidCallPattern, data.call_patterns.validate(a, original, wrong, candidate.variants, candidate.sites, 10_000_000));
    var checked = try data.call_patterns.run(a, original, null, .{});
    defer checked.deinit();
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer shared.deinit();
    var args = [_]u8{0} ** 16;
    args[0] = 1;
    @memset(args[8..16], 255);
    for ([_]ir.Program{ original, checked.program, shared.program, wrong }, 0..) |program, index| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
        defer result.deinit();
        try std.testing.expect(result.record == .failed);
        try std.testing.expectEqual(@as(u64, if (index == 3) 22 else 11), std.mem.readInt(u64, result.record.failed.value[0..8], .little));
    }
}
