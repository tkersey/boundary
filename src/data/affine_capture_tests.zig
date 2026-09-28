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

test "semantic closed compilation consumes affine state while structural preserves it" {
    const compilation = @import("closed_compilation.zig");
    const Trace = struct {
        visited: bool = false,
        fn enter(context: *anyopaque, stage: compilation.Stage) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (stage == .affine_state) self.visited = true;
        }
    };
    var trace: Trace = .{};
    var structural = try compilation.run(a, rotating, .{});
    defer structural.deinit();
    var stats: compilation.Statistics = .{};
    var semantic = try compilation.run(a, rotating, .{ .contract = .semantic, .statistics = &stats, .observer = .{ .context = &trace, .enter = Trace.enter } });
    defer semantic.deinit();
    try std.testing.expect(trace.visited);
    try std.testing.expectEqual(compilation.Outcome.applied, stats.outcome);
    try std.testing.expect(stats.changed_stages > 0);
    try std.testing.expect(!std.mem.eql(u8, &(try @import("program_image.zig").identity(a, structural.program)), &(try @import("program_image.zig").identity(a, semantic.program))));
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
    var program = rotating;
    program.functions = try allocator.dupe(ir.Function, &.{
        .{ .entry = 0, .inputs = inputs, .layout = .{ .slots = main_layout }, .result = 0 },
        .{ .entry = 2, .inputs = inputs, .layout = .{ .slots = worker_layout }, .result = 0 },
    });
    program.scopes.captures = try allocator.dupe(@import("program.zig").Capture, &.{.{ .fields = fields, .use = .reusable }});
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

test "checked capture synthesis reduces generated live-word permutations to one word" {
    for ([_]usize{ 2, 3, 8, 32, 64, 128 }) |n| {
        var arena = std.heap.ArenaAllocator.init(a);
        defer arena.deinit();
        const program = try parityFixture(arena.allocator(), n);
        var stats: @import("affine_state.zig").Statistics = .{};
        var result = try @import("affine_state.zig").run(a, program, 0, &stats, 10000000, .{});
        defer result.deinit();
        try std.testing.expectEqual(.applied, stats.outcome);
        try std.testing.expectEqual(@as(usize, 1), stats.reduced_words);
    }
}

fn twoModes() ir.Program {
    var program = rotating;
    program.constants = &.{ rotating.constants[0], .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } } };
    program.blocks = &.{
        rotating.blocks[0],                                                                                                                                                                                                                                                          rotating.blocks[1], rotating.blocks[2],
        .{ .function = 1, .instructions = &.{
            .{ .destination = 5, .opcode = .constant, .immediate = 1 },
            .{ .destination = 6, .opcode = .equal, .operands = &.{ 3, 5 } },
        }, .terminator = .{ .branch = .{ .condition = 6, .when_true = .{ .block = 6 }, .when_false = .{ .block = 7 } } } },
        rotating.blocks[4],                                                                                                                                                                                                                                                          rotating.blocks[5], rotating.blocks[3],
        .{ .function = 1, .instructions = &.{.{ .destination = 6, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 1, 0, 2, 3, 6 }, .next = .{ .block = 4, .assignments = &.{.{ .destination = 7, .source = .returned }} } } } },
    };
    return program;
}

test "all recursive modes close and a newly added reset invalidates the old candidate" {
    const program = comptime twoModes();
    var plan = (try affine.analyze(a, program, 0, 100000)).?;
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 2), plan.transitions.len);
    try std.testing.expectEqual(@as(usize, 2), plan.basis.len);
    var candidate = (try @import("affine_emit.zig").construct(a, program, 0, 100000)).?;
    defer candidate.deinit();
    try @import("affine_validate.zig").validate(a, program, candidate.program, 0, candidate.basis, 100000);
    var changed = program;
    var blocks = program.blocks[0..8].*;
    blocks[7].instructions = &.{
        .{ .destination = 6, .opcode = .constant, .immediate = 0 },
        .{ .destination = 5, .opcode = .constant, .immediate = 1 },
    };
    blocks[7].terminator.call.arguments = &.{ 5, 1, 2, 3, 6 };
    changed.blocks = &blocks;
    var expanded = (try affine.analyze(a, changed, 0, 100000)).?;
    defer expanded.deinit();
    try std.testing.expectEqual(@as(usize, 3), expanded.basis.len);
    try std.testing.expectError(error.InvalidAffineCandidate, @import("affine_validate.zig").validate(a, changed, candidate.program, 0, candidate.basis, 100000));
}

test "rank-zero state is emitted and full-rank observation is a legal no-op" {
    const pass = @import("affine_state.zig");
    var program = rotating;
    program.constants = &.{ rotating.constants[0], .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } } };
    var blocks = rotating.blocks[0..6].*;
    blocks[5].instructions = &.{.{ .destination = 5, .opcode = .constant, .immediate = 1 }};
    program.blocks = &blocks;
    var stats: pass.Statistics = .{};
    var reduced = try pass.run(a, program, 0, &stats, 100000, .{});
    defer reduced.deinit();
    try std.testing.expectEqual(.applied, stats.outcome);
    try std.testing.expectEqual(@as(usize, 0), stats.reduced_words);
    blocks[5].terminator = .{ .return_value = 0 };
    var retained = try pass.run(a, program, 0, &stats, 100000, .{});
    defer retained.deinit();
    try std.testing.expectEqual(.no_change, stats.outcome);
    var baseline = try @import("coalescing.zig").run(a, program, .{});
    defer baseline.deinit();
    try std.testing.expectEqual(try @import("program_image.zig").identity(a, baseline.program), try @import("program_image.zig").identity(a, retained.program));
}

pub fn inspectionThenLoop(storage: std.mem.Allocator) !ir.Program {
    var program = try parityFixture(storage, 2);
    const schema = @import("program.zig").Schema;
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

test "full external inspection precedes a one-coordinate private parity loop" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const program = try inspectionThenLoop(arena.allocator());
    var stats: @import("affine_state.zig").Statistics = .{};
    var result = try @import("affine_state.zig").run(a, program, 0, &stats, 1000000, .{});
    defer result.deinit();
    try std.testing.expectEqual(.applied, stats.outcome);
    try std.testing.expectEqual(@as(usize, 1), stats.reduced_words);
    try std.testing.expectEqual(@as(usize, 4), result.program.functions[@intCast(result.program.roots.entry)].inputs.len);
    try std.testing.expectEqual(@as(usize, 1), result.program.effects.len);
    const effect = result.program.effects[0];
    try std.testing.expectEqualSlices(u8, "affine/full-inspection", effect.identity);
    try std.testing.expectEqual(@as(usize, 2), result.program.schemas[@intCast(effect.payload)].product.len);
}

test "edge from a parity worker back to full inspection prevents capture loss" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const storage = arena.allocator();
    var program = try parityFixture(storage, 2);
    const functions = try storage.alloc(ir.Function, 3);
    @memcpy(functions[0..2], program.functions);
    functions[2] = .{ .entry = 6, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 };
    program.functions = functions;
    const blocks = try storage.alloc(ir.Block, 8);
    @memcpy(blocks[0..6], program.blocks);
    blocks[5].terminator = .{ .call = .{ .function = 2, .arguments = &.{ 0, 1 }, .next = .{ .block = 7, .assignments = &.{.{ .destination = 6, .source = .returned }} } } };
    blocks[6] = .{ .function = 2, .instructions = &.{.{ .destination = 2, .opcode = .integer_bit_or, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 2 } };
    blocks[7] = .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 6 } };
    program.blocks = blocks;
    var plan = (try affine.analyze(a, program, 0, 1000000)).?;
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 2), plan.basis.len);
    var stats: @import("affine_state.zig").Statistics = .{};
    var result = try @import("affine_state.zig").run(a, program, 0, &stats, 1000000, .{});
    defer result.deinit();
    try std.testing.expectEqual(.no_change, stats.outcome);
}
