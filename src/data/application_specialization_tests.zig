// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const ir = @import("activation.zig");
const p = @import("program.zig");
const specialize = @import("application_specialization.zig");
const facts = @import("value_facts.zig");
const coalescing = @import("coalescing.zig");
const a = std.testing.allocator;
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

test "captured application becomes an ordered direct call and final P01 runs" {
    var statistics: specialize.Statistics = .{};
    var p01: coalescing.Statistics = .{};
    var result = try specialize.run(a, captured, &statistics, .{ .statistics = &p01 });
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), statistics.direct_applications);
    try std.testing.expectEqual(@as(usize, 1), statistics.eliminated_constructions);
    try std.testing.expect(p01.outcome != .not_run);
    var calls: usize = 0;
    for (result.program.blocks) |block| {
        try std.testing.expect(block.terminator != .apply);
        for (block.instructions) |instruction| try std.testing.expect(instruction.opcode != .computation);
        if (block.terminator == .call) calls += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), calls);
    const before = try @import("program_image.zig").encodedLength(captured);
    const after = try @import("program_image.zig").encodedLength(result.program);
    try std.testing.expect(after < before);
    std.debug.print("captured specialization: BPI3 {d} -> {d} bytes; apply/construction 1 -> 0\n", .{ before, after });
}

test "independent checker rejects swapped equal-type captures and arguments" {
    var blocks = captured.blocks[0..3].*;
    blocks[0].instructions = &.{};
    blocks[0].terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 1 }, .next = captured.blocks[0].terminator.apply.next } };
    var candidate = captured;
    candidate.blocks = &blocks;
    try specialize.validate(a, captured, candidate, &.{.{ .block = 0, .construction = 0 }});
    blocks[0].terminator.call.arguments = &.{ 1, 0 };
    try std.testing.expectError(error.InvalidSpecialization, specialize.validate(a, captured, candidate, &.{.{ .block = 0, .construction = 0 }}));
}

test "an overwritten capture version retains the original application" {
    var blocks = captured.blocks[0..3].*;
    blocks[0].instructions = &.{ captured.blocks[0].instructions[0], .{ .destination = 0, .opcode = .move, .operands = &.{1} } };
    var input = captured;
    input.blocks = &blocks;
    var statistics: specialize.Statistics = .{};
    var result = try specialize.run(a, input, &statistics, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), statistics.direct_applications);
    try std.testing.expectEqual(@as(usize, 1), statistics.unavailable_captures);
}

test "facts cannot be reused after constructor catalog mutation" {
    var known = try facts.analyze(a, captured);
    defer known.deinit();
    var changed = captured;
    changed.constructors = &.{ captured.constructors[0], captured.constructors[0] };
    try std.testing.expectError(error.StaleFacts, known.requireEpoch(a, changed));
}

test "unknown input masking gains bits while a vector bound is not its length" {
    const program: ir.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit, .{ .vector = .{ .element = 0, .maximum = 16 } } },
        .constants = &.{.{ .schema = 0, .bytes = &.{ 15, 0, 0, 0, 0, 0, 0, 0 } }},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 2, 0, 0, 0, 0 } }, .result = 0 }},
        .blocks = &.{.{ .function = 0, .instructions = &.{
            .{ .destination = 2, .opcode = .constant, .immediate = 0 },
            .{ .destination = 3, .opcode = .integer_bit_and, .operands = &.{ 1, 2 } },
            .{ .destination = 4, .opcode = .sequence_length, .operands = &.{0} },
        }, .terminator = .{ .return_value = 3 } }},
    };
    var known = try facts.analyze(a, program);
    defer known.deinit();
    const block = known.blocks[0];
    const mask = block.definitions[block.results[1]].value;
    try std.testing.expectEqual(@as(?u64, 15), mask.maximum);
    try std.testing.expectEqual(~@as(u64, 15), mask.known_zero);
    try std.testing.expectEqual(@as(?u64, null), mask.unsigned);
    const length = block.definitions[block.results[2]].value;
    try std.testing.expectEqual(@as(?u64, 16), length.maximum);
    try std.testing.expectEqual(@as(?u64, null), length.unsigned);
}

fn allocationAttempt(allocator: std.mem.Allocator) !void {
    var result = try specialize.run(allocator, captured, null, .{});
    defer result.deinit();
}
test "specialization releases every partial owner on allocation failure" {
    try std.testing.checkAllAllocationFailures(a, allocationAttempt, .{});
}
