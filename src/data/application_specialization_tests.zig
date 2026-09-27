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

test "parallel edge assignments read one predecessor view and loops widen constants" {
    const swap = ir.Edge{ .block = 1, .assignments = &.{ .{ .destination = 0, .source = .{ .slot = 1 } }, .{ .destination = 1, .source = .{ .slot = 0 } } } };
    var program: ir.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit, .boolean },
        .constants = &.{ .{ .schema = 0, .bytes = &.{ 4, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 9, 0, 0, 0, 0, 0, 0, 0 } } },
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{2}, .layout = .{ .slots = &.{ 0, 0, 2 } }, .result = 0 }},
        .blocks = &.{
            .{ .function = 0, .instructions = &.{ .{ .destination = 0, .opcode = .constant, .immediate = 0 }, .{ .destination = 1, .opcode = .constant, .immediate = 1 } }, .terminator = .{ .jump = swap } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        },
    };
    var acyclic = try facts.analyze(a, program);
    defer acyclic.deinit();
    try std.testing.expectEqual(@as(?u64, 9), acyclic.blocks[1].definitions[0].value.unsigned);
    try std.testing.expectEqual(@as(?u64, 4), acyclic.blocks[1].definitions[1].value.unsigned);
    program.blocks = &.{ program.blocks[0], .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = swap, .when_false = .{ .block = 2 } } } }, .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } } };
    var cyclic = try facts.analyze(a, program);
    defer cyclic.deinit();
    for (cyclic.blocks[1].definitions[0..2]) |definition| {
        try std.testing.expectEqual(@as(?u64, null), definition.value.unsigned);
        try std.testing.expectEqual(@as(?u64, 9), definition.value.maximum);
        try std.testing.expectEqual(~@as(u64, 13), definition.value.known_zero);
    }
    try std.testing.expect(cyclic.blocks[2].reachable);
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
test "feasible edges narrow constructor sets without inventing an opaque environment" {
    var polymorphic = try facts.analyze(a, comptime branchProgram(false));
    defer polymorphic.deinit();
    const many = polymorphic.blocks[3].definitions[2].value;
    try std.testing.expect(many.constructors_known);
    try std.testing.expectEqual(@as(u3, 2), many.constructor_count);
    try std.testing.expectEqual(@as(?p.Id, null), many.constructor);
    var singleton = try facts.analyze(a, comptime branchProgram(true));
    defer singleton.deinit();
    try std.testing.expect(!singleton.blocks[2].reachable);
    const one = singleton.blocks[3].definitions[2].value;
    try std.testing.expectEqual(@as(?p.Id, 0), one.constructor);
    try std.testing.expectEqual(@as(?usize, null), one.construction);
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
test "checked feasible branch removes the alternate constructor and unlocks a direct call" {
    const branch = @import("branch_reduction.zig");
    const program = comptime closedBranchProgram(true);
    var branch_stats: branch.Statistics = .{};
    var reduced = try branch.run(a, program, &branch_stats, .{});
    defer reduced.deinit();
    try std.testing.expectEqual(@as(usize, 1), branch_stats.branches_removed);
    try std.testing.expectEqual(@as(usize, 1), reduced.program.constructors.len);
    var stats: specialize.Statistics = .{};
    var specialized = try specialize.run(a, reduced.program, &stats, .{});
    defer specialized.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.direct_applications);
    try std.testing.expectEqual(@as(usize, 1), stats.retained_constructions);
    for (specialized.program.blocks) |block| try std.testing.expect(block.terminator != .apply and block.terminator != .branch);
    std.debug.print("branch/constructor specialization: BPI3 {d} -> {d} bytes\n", .{ try @import("program_image.zig").encodedLength(program), try @import("program_image.zig").encodedLength(specialized.program) });
}

test "unknown external condition and forged branch certificates retain both targets" {
    const branch = @import("branch_reduction.zig");
    const program = comptime closedBranchProgram(false);
    var stats: branch.Statistics = .{};
    var unchanged = try branch.run(a, program, &stats, .{});
    defer unchanged.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.branches_removed);
    try std.testing.expectEqual(@as(usize, 2), unchanged.program.constructors.len);
    var blocks = program.blocks[0..7].*;
    blocks[0].terminator = .{ .jump = program.blocks[0].terminator.branch.when_true };
    var forged = program;
    forged.blocks = &blocks;
    try std.testing.expectError(error.InvalidBranchReduction, branch.validate(a, program, forged, &.{.{ .block = 0, .condition = true }}));
}

test "branch reduction checks an invalid unselected constructor before erasing its path" {
    var program = comptime closedBranchProgram(true);
    var blocks = program.blocks[0..7].*;
    blocks[2].instructions = &.{.{ .destination = 2, .opcode = .computation, .immediate = 99 }};
    program.blocks = &blocks;
    try std.testing.expectError(error.InvalidReference, @import("branch_reduction.zig").run(a, program, null, .{}));
}

fn branchAllocationAttempt(allocator: std.mem.Allocator) !void {
    var result = try @import("branch_reduction.zig").run(allocator, comptime closedBranchProgram(true), null, .{});
    defer result.deinit();
}
test "branch proof and candidate owners release on every allocation failure" {
    try std.testing.checkAllAllocationFailures(a, branchAllocationAttempt, .{});
}
