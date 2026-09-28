const std = @import("std");
const ir = @import("activation.zig");
const unpack = @import("capture_unpack.zig");
const a = std.testing.allocator;
pub const product_cycle: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .boolean, .{ .product = &.{ 0, 0, 0 } }, .{ .internal = .{ .computation = .{ .parameters = &.{ 0, 2 }, .result = 0, .capture_bound = &.{3}, .use = .reusable } } } },
    .constants = &.{.{ .schema = 2, .bytes = &.{0} }},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 3, 0, 2, 4, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 3, 0, 2, 0, 0, 0, 0, 3, 2, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .computation, .operands = &.{0} }}, .terminator = .{ .apply = .{ .computation = 3, .arguments = &.{ 1, 2 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 3 }, .when_false = .{ .block = 5 } } } },
        .{ .function = 1, .instructions = &.{
            .{ .destination = 3, .opcode = .field, .operands = &.{0}, .immediate = 0 },
            .{ .destination = 4, .opcode = .field, .operands = &.{0}, .immediate = 1 },
            .{ .destination = 5, .opcode = .field, .operands = &.{0}, .immediate = 2 },
            .{ .destination = 6, .opcode = .integer_bit_xor, .operands = &.{ 3, 1 } },
            .{ .destination = 7, .opcode = .product, .operands = &.{ 4, 5, 6 } },
            .{ .destination = 8, .opcode = .constant },
        }, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 7, 1, 8 }, .next = .{ .block = 4, .assignments = &.{.{ .destination = 9, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 9 } },
        .{ .function = 1, .instructions = &.{
            .{ .destination = 3, .opcode = .field, .operands = &.{0}, .immediate = 0 },
            .{ .destination = 4, .opcode = .field, .operands = &.{0}, .immediate = 1 },
            .{ .destination = 6, .opcode = .integer_bit_xor, .operands = &.{ 3, 4 } },
        }, .terminator = .{ .return_value = 6 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{3}, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 4 }},
};

test "private product capture unpacks into ordered scalar worker inputs" {
    var candidate = (try unpack.construct(a, product_cycle, 0)).?;
    defer candidate.deinit();
    try std.testing.expectEqual(@as(usize, 5), candidate.program.functions[1].inputs.len);
    try std.testing.expectEqual(@as(usize, 3), candidate.program.scopes.captures[@intCast(candidate.program.constructors[0].capture)].fields.len);
    try unpack.validate(a, product_cycle, candidate.program, 0);
    var wrong = candidate.program;
    const blocks = try a.dupe(ir.Block, wrong.blocks);
    defer a.free(blocks);
    const operations = try a.dupe(ir.Instruction, blocks[0].instructions);
    defer a.free(operations);
    operations[0].immediate = 1;
    blocks[0].instructions = operations;
    wrong.blocks = blocks;
    var admitted = try @import("activation_ownership.zig").analyze(a, wrong);
    defer admitted.deinit();
    try std.testing.expectError(error.InvalidCaptureUnpack, unpack.validate(a, product_cycle, wrong, 0));
}
fn allocationAttempt(allocator: std.mem.Allocator) !void {
    var candidate = (try unpack.construct(allocator, product_cycle, 0)).?;
    defer candidate.deinit();
}
test "product capture unpacking releases every partial owner" {
    try std.testing.checkAllAllocationFailures(a, allocationAttempt, .{});
}

test "checked product unpacking feeds aggregate reduction and affine synthesis" {
    var flat = try unpack.run(a, product_cycle, .{});
    defer flat.deinit();
    var forwarded = try @import("aggregate_reduction.zig").run(a, flat.program, null, .{});
    defer forwarded.deinit();
    var cleaned = try @import("dead_computation.zig").run(a, forwarded.program, null, .{});
    defer cleaned.deinit();
    var stats: @import("affine_state.zig").Statistics = .{};
    var result = try @import("affine_state.zig").run(a, cleaned.program, 0, &stats, 1000000, .{});
    defer result.deinit();
    try std.testing.expectEqual(.applied, stats.outcome);
    try std.testing.expectEqual(@as(usize, 3), stats.original_words);
    try std.testing.expectEqual(@as(usize, 2), stats.reduced_words);
    var compilation: @import("closed_compilation.zig").Statistics = .{};
    var compiled = try @import("closed_compilation.zig").run(a, product_cycle, .{ .contract = .semantic, .statistics = &compilation });
    defer compiled.deinit();
    try std.testing.expectEqual(.applied, compilation.outcome);
}

test "whole-product observation keeps the original captured representation" {
    const p = @import("program.zig");
    var original = product_cycle;
    var schemas = product_cycle.schemas[0..5].*;
    schemas[4].internal.computation.result = 3;
    original.schemas = &schemas;
    original.roots.result = 3;
    var functions = product_cycle.functions[0..2].*;
    functions[0].result = 3;
    functions[0].layout.slots = &.{ 3, 0, 2, 4, 3 };
    functions[1].result = 3;
    functions[1].layout.slots = &.{ 3, 0, 2, 0, 0, 0, 0, 3, 2, 3 };
    original.functions = &functions;
    var blocks = product_cycle.blocks[0..6].*;
    blocks[5].terminator = .{ .return_value = 0 };
    original.blocks = &blocks;
    var admitted = try @import("activation_ownership.zig").analyze(a, original);
    defer admitted.deinit();
    try std.testing.expect((try unpack.construct(a, original, 0)) == null);
    const image = @import("program_image.zig");
    var baseline = try @import("coalescing.zig").run(a, original, .{});
    defer baseline.deinit();
    var retained = try unpack.run(a, original, .{});
    defer retained.deinit();
    try std.testing.expectEqual(try image.identity(a, baseline.program), try image.identity(a, retained.program));
    _ = p;
}
