// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const compile = @import("closed_compilation.zig");
const p01 = @import("coalescing.zig");
const image = @import("program_image.zig");
const captured = @import("application_specialization_tests.zig").captured;
const a = std.testing.allocator;

test "both closed compilation contracts invoke P01 and only semantic rewrites apply" {
    var structural_stats: compile.Statistics = .{};
    var structural_p01: p01.Statistics = .{};
    var structural = try compile.run(a, captured, .{ .statistics = &structural_stats, .coalescing = .{ .statistics = &structural_p01 } });
    defer structural.deinit();
    try std.testing.expectEqual(compile.Outcome.structural, structural_stats.outcome);
    try std.testing.expect(structural_p01.outcome != .not_run);
    var applies: usize = 0;
    for (structural.program.blocks) |block| {
        if (block.terminator == .apply) applies += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), applies);
    var stats: compile.Statistics = .{};
    var semantic_p01: p01.Statistics = .{};
    var semantic = try compile.run(a, captured, .{ .contract = .semantic, .statistics = &stats, .coalescing = .{ .statistics = &semantic_p01 } });
    defer semantic.deinit();
    try std.testing.expectEqual(compile.Outcome.applied, stats.outcome);
    try std.testing.expect(semantic_p01.outcome != .not_run);
    try std.testing.expect(stats.changed_stages > 0 and stats.rounds >= 2);
    for (semantic.program.blocks) |block| try std.testing.expect(block.terminator != .apply);
    std.debug.print("closed semantic compilation: {d} -> {d} bytes, {d} rounds\n", .{ stats.baseline_bytes, stats.final_bytes, stats.rounds });
}

test "zero budget and a late round limit return the exact structural baseline" {
    var baseline = try compile.run(a, captured, .{});
    defer baseline.deinit();
    const identity = try image.identity(a, baseline.program);
    for ([_]compile.Options{ .{ .contract = .semantic, .work_limit = 0 }, .{ .contract = .semantic, .round_limit = 1 } }) |selected| {
        var options = selected;
        var stats: compile.Statistics = .{};
        options.statistics = &stats;
        var result = try compile.run(a, captured, options);
        defer result.deinit();
        try std.testing.expectEqual(compile.Outcome.work_limit, stats.outcome);
        try std.testing.expectEqual(identity, try image.identity(a, result.program));
        if (selected.round_limit == 1) try std.testing.expect(stats.changed_stages > 0);
    }
    try std.testing.expectError(error.Capacity, compile.run(a, captured, .{ .contract = .semantic, .work_limit = 0, .max_image_bytes = 0 }));
}

test "size objective and explicit zero growth protect the original exact image size" {
    const projection = @import("capture_projection_tests.zig").reused;
    var baseline = try compile.run(a, projection, .{});
    defer baseline.deinit();
    for ([_]compile.Options{ .{ .contract = .semantic, .objective = .size }, .{ .contract = .semantic, .image_growth_bytes = 0 } }) |options| {
        var result = try compile.run(a, projection, options);
        defer result.deinit();
        try std.testing.expect(try image.encodedLength(result.program) <= try image.encodedLength(baseline.program));
    }
}

test "incomplete value facts and exhausted backwards proofs never escape" {
    try std.testing.expectError(error.SemanticWorkLimit, @import("value_facts.zig").analyzeWithLimit(a, captured, 0));
    var proof: @import("constant_origin.zig").Prover = .{ .allocator = a, .program = captured, .work_limit = 1 };
    defer proof.deinit();
    try std.testing.expectEqual(@as(?@import("constant_origin.zig").Constant, null), try proof.resolve(0, 1, 2));
    try std.testing.expect(proof.exhausted);
    var invalid = captured;
    invalid.constructors = &.{.{ .function = 99, .capture = 0, .schema = 2 }};
    try std.testing.expectError(error.InvalidReference, compile.run(a, invalid, .{ .contract = .semantic, .work_limit = 0 }));
}

fn allocationAttempt(allocator: std.mem.Allocator) !void {
    var result = try compile.run(allocator, captured, .{ .contract = .semantic });
    defer result.deinit();
}
test "closed compilation releases baseline and successor owners on every allocation failure" {
    try std.testing.checkAllAllocationFailures(a, allocationAttempt, .{});
}

test "observers do not change selected semantic bytes" {
    const Counter = struct {
        count: usize = 0,
        fn enter(pointer: *anyopaque, _: compile.Stage) void {
            const self: *@This() = @ptrCast(@alignCast(pointer));
            self.count += 1;
        }
    };
    var counter: Counter = .{};
    var plain = try compile.run(a, captured, .{ .contract = .semantic });
    defer plain.deinit();
    var observed = try compile.run(a, captured, .{ .contract = .semantic, .observer = .{ .context = &counter, .enter = Counter.enter } });
    defer observed.deinit();
    try std.testing.expect(counter.count > 0);
    try std.testing.expectEqual(try image.identity(a, plain.program), try image.identity(a, observed.program));
}

test "work accounting uses logical records rather than compressed literal wire lengths" {
    const ir = @import("activation.zig");
    const p = @import("program.zig");
    var bytes: [128][8]u8 = undefined;
    var literals: [128]p.Literal = undefined;
    var instructions: [128]ir.Instruction = undefined;
    for (&bytes, &literals, &instructions, 0..) |*storage, *literal, *instruction, index| {
        std.mem.writeInt(u64, storage, index, .little);
        literal.* = .{ .schema = 0, .bytes = storage };
        instruction.* = .{ .destination = 0, .opcode = .constant, .immediate = index };
    }
    const program: ir.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit },
        .constants = &literals,
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = &.{0} }, .result = 0 }},
        .blocks = &.{.{ .function = 0, .instructions = &instructions, .terminator = .{ .return_value = 0 } }},
    };
    var stats: compile.Statistics = .{};
    var limited = try compile.run(a, program, .{ .contract = .semantic, .work_limit = 0, .statistics = &stats });
    defer limited.deinit();
    try std.testing.expectEqual(compile.Outcome.work_limit, stats.outcome);
    var result = try compile.run(a, program, .{ .contract = .semantic, .statistics = &stats });
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), result.program.blocks[0].instructions.len);
    try std.testing.expect(stats.selected_candidate == .shrinking);
}

test "inapplicable semantic passes are skipped without skipping mandatory P01" {
    const ir = @import("activation.zig");
    const program: ir.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit },
        .effects = &.{},
        .constants = &.{.{ .schema = 0, .bytes = &.{ 7, 0, 0, 0, 0, 0, 0, 0 } }},
        .functions = &.{.{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = &.{0} }, .result = 0 }},
        .blocks = &.{.{ .function = 0, .instructions = &.{.{ .destination = 0, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .return_value = 0 } }},
    };
    var stats: compile.Statistics = .{};
    var structural: p01.Statistics = .{};
    var result = try compile.run(a, program, .{ .contract = .semantic, .statistics = &stats, .coalescing = .{ .statistics = &structural } });
    defer result.deinit();
    try std.testing.expectEqual(compile.Outcome.no_change, stats.outcome);
    try std.testing.expectEqual(@as(usize, 0), stats.stages_run);
    try std.testing.expect(stats.stages_skipped > 0);
    try std.testing.expect(structural.outcome != .not_run);
}

test "a proved no-op stage is not repeated on unchanged records" {
    const ir = @import("activation.zig");
    const program: ir.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit },
        .effects = &.{},
        .constants = &.{.{ .schema = 0, .bytes = &.{ 7, 0, 0, 0, 0, 0, 0, 0 } }},
        .functions = &.{.{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 }},
        .blocks = &.{
            .{ .function = 0, .instructions = &.{.{ .destination = 1, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .jump = .{ .block = 1, .assignments = &.{.{ .destination = 2, .source = .{ .slot = 1 } }} } } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        },
    };
    var stats: compile.Statistics = .{};
    var result = try compile.run(a, program, .{ .contract = .semantic, .statistics = &stats });
    defer result.deinit();
    try std.testing.expectEqual(compile.Outcome.no_change, stats.outcome);
    try std.testing.expectEqual(@as(usize, 1), stats.stages_run);
    try std.testing.expectEqual(@as(usize, 0), stats.changed_stages);
}

const shrinking_fixture: @import("activation.zig").Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit },
    .effects = &.{},
    .constants = &.{.{ .schema = 0, .bytes = &.{ 7, 0, 0, 0, 0, 0, 0, 0 } }},
    .functions = &.{.{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0 }},
    .blocks = &.{.{ .function = 0, .instructions = &.{
        .{ .destination = 0, .opcode = .constant, .immediate = 0 },
        .{ .destination = 1, .opcode = .constant, .immediate = 0 },
    }, .terminator = .{ .return_value = 1 } }},
};
fn shrinkingAllocationAttempt(allocator: std.mem.Allocator) !void {
    var result = try compile.run(allocator, shrinking_fixture, .{ .contract = .semantic });
    defer result.deinit();
}
test "independent shrinking candidate releases every partial owner and charges its work" {
    try std.testing.checkAllAllocationFailures(a, shrinkingAllocationAttempt, .{});
    var stats: compile.Statistics = .{};
    var limited = try compile.run(a, shrinking_fixture, .{ .contract = .semantic, .work_limit = 1, .statistics = &stats });
    defer limited.deinit();
    var baseline = try compile.run(a, shrinking_fixture, .{});
    defer baseline.deinit();
    try std.testing.expectEqual(compile.Outcome.work_limit, stats.outcome);
    try std.testing.expectEqual(compile.Stage.dead_computation, stats.stopped_stage.?);
    try std.testing.expectEqual(try image.identity(a, baseline.program), try image.identity(a, limited.program));
}
