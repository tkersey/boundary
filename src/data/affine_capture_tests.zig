const std = @import("std");
const ir = @import("activation.zig");
const affine = @import("affine_capture.zig");
const a = std.testing.allocator;

pub const rotating: ir.Program = .{
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

test "private recursive capture worker derives two coordinates from admitted records" {
    var plan = (try affine.analyze(a, rotating, 0, 100000)).?;
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 3), plan.dimension);
    try std.testing.expectEqual(@as(usize, 2), plan.basis.len);
    try std.testing.expectEqual(@as(usize, 1), plan.transitions.len);
    try std.testing.expectEqual(@as(u128, 1), plan.transitions[0].values[2].input);
}

test "individual state observation forces full rank" {
    var program = rotating;
    var blocks = rotating.blocks[0..6].*;
    blocks[5].terminator = .{ .return_value = 0 };
    program.blocks = &blocks;
    var plan = (try affine.analyze(a, program, 0, 100000)).?;
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 3), plan.basis.len);
}

fn allocationAttempt(allocator: std.mem.Allocator) !void {
    var plan = (try affine.analyze(allocator, rotating, 0, 100000)).?;
    defer plan.deinit();
}
test "affine capture census releases every partial owner" {
    try std.testing.checkAllAllocationFailures(a, allocationAttempt, .{});
    try std.testing.expectError(error.WorkLimit, affine.analyze(a, rotating, 0, 0));
}

test "affine emitter constructs a two-word recursive capture interface" {
    var candidate = (try @import("affine_emit.zig").construct(a, rotating, 0, 100000)).?;
    defer candidate.deinit();
    var admitted = try @import("activation_ownership.zig").analyze(a, candidate.program);
    defer admitted.deinit();
    const capture = candidate.program.scopes.captures[@intCast(candidate.program.constructors[0].capture)];
    try std.testing.expectEqual(@as(usize, 2), capture.fields.len);
    try std.testing.expectEqual(@as(usize, 4), candidate.program.functions[1].inputs.len);
    try std.testing.expectEqual(@as(usize, 4), candidate.program.blocks[3].terminator.call.arguments.len);
}

test "independent affine checker validates emitted equations and rejects wrong capture order" {
    const check = @import("affine_validate.zig");
    var candidate = (try @import("affine_emit.zig").construct(a, rotating, 0, 100000)).?;
    defer candidate.deinit();
    try check.validate(a, rotating, candidate.program, 0, candidate.basis, 100000);
    var altered = candidate.program;
    const blocks = try a.dupe(ir.Block, altered.blocks);
    defer a.free(blocks);
    const operations = try a.dupe(ir.Instruction, blocks[0].instructions);
    defer a.free(operations);
    const last = operations.len - 1;
    const wrong = [_]u64{ operations[last].operands[1], operations[last].operands[0] };
    operations[last].operands = &wrong;
    blocks[0].instructions = operations;
    altered.blocks = blocks;
    var admitted = try @import("activation_ownership.zig").analyze(a, altered);
    defer admitted.deinit();
    try std.testing.expectError(error.InvalidAffineCandidate, check.validate(a, rotating, altered, 0, candidate.basis, 100000));
}

test "affine acceptance rejects wrong recursive input terms and basis" {
    const check = @import("affine_validate.zig");
    var candidate = (try @import("affine_emit.zig").construct(a, rotating, 0, 100000)).?;
    defer candidate.deinit();
    var altered = candidate.program;
    const blocks = try a.dupe(ir.Block, altered.blocks);
    defer a.free(blocks);
    const arguments = try a.dupe(u64, blocks[3].terminator.call.arguments);
    defer a.free(arguments);
    arguments[1] = arguments[0];
    blocks[3].terminator.call.arguments = arguments;
    altered.blocks = blocks;
    var admitted = try @import("activation_ownership.zig").analyze(a, altered);
    defer admitted.deinit();
    try std.testing.expectError(error.InvalidAffineCandidate, check.validate(a, rotating, altered, 0, candidate.basis, 100000));
    try std.testing.expectError(error.InvalidAffineCandidate, check.validate(a, rotating, candidate.program, 0, &.{ 1, 2 }, 100000));
    try std.testing.expectError(error.WorkLimit, check.validate(a, rotating, candidate.program, 0, candidate.basis, 0));
}

fn checkedAllocationAttempt(allocator: std.mem.Allocator) !void {
    var result = try @import("affine_state.zig").run(allocator, rotating, 0, null, 100000, .{});
    defer result.deinit();
}
test "checked affine transformation owns output and rolls back deterministic limits" {
    const pass = @import("affine_state.zig");
    var stats: pass.Statistics = .{};
    var p01: @import("coalescing.zig").Statistics = .{};
    var result = try pass.run(a, rotating, 0, &stats, 100000, .{ .statistics = &p01 });
    defer result.deinit();
    try std.testing.expectEqual(.applied, stats.outcome);
    try std.testing.expectEqual(@as(usize, 3), stats.original_words);
    try std.testing.expectEqual(@as(usize, 2), stats.reduced_words);
    try std.testing.expect(p01.outcome != .not_run);
    var limited = try pass.run(a, rotating, 0, &stats, 0, .{});
    defer limited.deinit();
    var baseline = try @import("coalescing.zig").run(a, rotating, .{});
    defer baseline.deinit();
    try std.testing.expectEqual(.work_limit, stats.outcome);
    try std.testing.expectEqual(try @import("program_image.zig").identity(a, baseline.program), try @import("program_image.zig").identity(a, limited.program));
    try std.testing.checkAllAllocationFailures(a, checkedAllocationAttempt, .{});
}
