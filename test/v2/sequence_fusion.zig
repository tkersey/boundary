const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;
pub const map_fold: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .boolean, .unit, .{ .vector = .{ .element = 0, .maximum = 8 } }, .{ .product = &.{ 0, 2 } }, .{ .sum = &.{ 1, 3 } }, .{ .vector = .{ .element = 0, .maximum = 8 } }, .{ .product = &.{ 0, 5 } }, .{ .sum = &.{ 1, 6 } } },
    .constants = &.{.{ .schema = 1, .bytes = &.{} }},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 2, 0, 5, 4, 3, 0, 2, 0, 5, 7, 6, 0, 5, 0 } }, .result = 0 },
        .{ .entry = 9, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0 },
        .{ .entry = 10, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .sequence }}, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .sequence_pop, .operands = &.{0} }}, .terminator = .{ .switch_variant = .{ .value = 3, .cases = &.{ .{ .block = 4 }, .{ .block = 2 } } } } },
        .{ .function = 0, .instructions = &.{
            .{ .destination = 4, .opcode = .variant_payload, .operands = &.{3}, .immediate = 1, .failures = &.{.{ .kind = .invalid_variant, .value = 0 }} },
            .{ .destination = 5, .opcode = .field, .operands = &.{4}, .immediate = 0 },
            .{ .destination = 6, .opcode = .field, .operands = &.{4}, .immediate = 1 },
        }, .terminator = .{ .call = .{ .function = 1, .arguments = &.{5}, .next = .{ .block = 3, .assignments = &.{.{ .destination = 7, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .sequence_append, .operands = &.{ 2, 7 }, .failures = &.{.{ .kind = .capacity_exceeded, .value = 0 }} }}, .terminator = .{ .jump = .{ .block = 1, .assignments = &.{.{ .destination = 0, .source = .{ .slot = 6 } }} } } },
        .{ .function = 0, .instructions = &.{ .{ .destination = 8, .opcode = .move, .operands = &.{2} }, .{ .destination = 13, .opcode = .move, .operands = &.{1} } }, .terminator = .{ .jump = .{ .block = 5 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 9, .opcode = .sequence_pop, .operands = &.{8} }}, .terminator = .{ .switch_variant = .{ .value = 9, .cases = &.{ .{ .block = 8 }, .{ .block = 6 } } } } },
        .{ .function = 0, .instructions = &.{
            .{ .destination = 10, .opcode = .variant_payload, .operands = &.{9}, .immediate = 1, .failures = &.{.{ .kind = .invalid_variant, .value = 0 }} },
            .{ .destination = 11, .opcode = .field, .operands = &.{10}, .immediate = 0 },
            .{ .destination = 12, .opcode = .field, .operands = &.{10}, .immediate = 1 },
        }, .terminator = .{ .call = .{ .function = 2, .arguments = &.{ 13, 11 }, .next = .{ .block = 7, .assignments = &.{.{ .destination = 13, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .jump = .{ .block = 5, .assignments = &.{.{ .destination = 8, .source = .{ .slot = 12 } }} } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 13 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 1, .opcode = .boolean_not, .operands = &.{0} }}, .terminator = .{ .return_value = 1 } },
        .{ .function = 2, .instructions = &.{ .{ .destination = 2, .opcode = .boolean_not, .operands = &.{1} }, .{ .destination = 3, .opcode = .select, .operands = &.{ 0, 2, 0 } } }, .terminator = .{ .return_value = 3 } },
    },
};

pub fn failingSteps(allocator: std.mem.Allocator) !ir.Program {
    var original = map_fold;
    original.roots.failure = 0;
    original.constants = &.{ .{ .schema = 0, .bytes = &.{0} }, .{ .schema = 0, .bytes = &.{1} } };
    const functions = try allocator.dupe(ir.Function, original.functions);
    functions[1].layout.slots = &.{ 0, 0, 0 };
    original.functions = functions;
    const blocks = try allocator.alloc(ir.Block, 13);
    @memcpy(blocks[0..11], original.blocks);
    blocks[9] = .{ .function = 1, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 0, .when_true = .{ .block = 11 }, .when_false = .{ .block = 12 } } } };
    blocks[10] = .{ .function = 2, .instructions = &.{.{ .destination = 2, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .fail = 2 } };
    blocks[11] = .{ .function = 1, .instructions = &.{.{ .destination = 2, .opcode = .constant, .immediate = 1 }}, .terminator = .{ .fail = 2 } };
    blocks[12] = .{ .function = 1, .instructions = &.{.{ .destination = 1, .opcode = .boolean_not, .operands = &.{0} }}, .terminator = .{ .return_value = 1 } };
    original.blocks = blocks;
    return original;
}

pub fn bounded(allocator: std.mem.Allocator, maximum: u64) !ir.Program {
    var program = map_fold;
    const schemas = try allocator.dupe(data.program.Schema, program.schemas);
    schemas[2].vector.maximum = maximum;
    schemas[5].vector.maximum = maximum;
    program.schemas = schemas;
    return program;
}
fn encoded(allocator: std.mem.Allocator, program: ir.Program) ![]u8 {
    const bytes = try allocator.alloc(u8, try data.program_image.encodedLength(program));
    errdefer allocator.free(bytes);
    _ = try data.program_image.encode(allocator, program, bytes);
    return bytes;
}
fn runSteps(image: []const u8, input: []const u8, expected: []const u8) !usize {
    var result = try world.invocation.invoke(a, .{ .image = image, .instance = .{ .initial_args = input }, .quantum = 1 });
    defer result.deinit();
    var steps: usize = 1;
    while (result.record == .progressed) {
        try std.testing.expect(steps < 512);
        const next = try world.invocation.invoke(a, .{ .image = image, .instance = .{ .state = result.record.progressed.? }, .quantum = 1 });
        result.deinit();
        result = next;
        steps += 1;
    }
    try std.testing.expect(result.record == .completed);
    try std.testing.expectEqualSlices(u8, expected, result.record.completed);
    return steps;
}
test "map/fold fusion preserves every bounded Boolean input through shared compilation and source-free linking" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try bounded(arena.allocator(), 4);
    var baseline = try data.closed_compilation.run(a, original, .{});
    defer baseline.deinit();
    var stats: data.sequence_fusion.Statistics = .{};
    var fused = try data.sequence_fusion.run(a, original, &stats, .{});
    defer fused.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.loops_fused);
    var compilation: data.closed_compilation.Statistics = .{};
    var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic, .statistics = &compilation });
    defer compiled.deinit();
    const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 } } };
    const bmo = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(bmo);
    _ = try data.component.encode(a, object, bmo);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "map-fold", .object = bmo }}, &.{}, .{ .instance = "map-fold", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(bmo, 0xff);
    const programs = [_]ir.Program{ baseline.program, fused.program, compiled.program, linked.program };
    var images: [4][]u8 = undefined;
    for (programs, &images, 0..) |program, *bytes, arm| {
        bytes.* = try encoded(arena.allocator(), program);
        if (arm > 0) for (program.blocks) |block| for (block.instructions) |op| try std.testing.expect(op.opcode != .sequence and op.opcode != .sequence_append);
    }
    var cases: usize = 0;
    for (0..5) |length| {
        const count = @as(usize, 1) << @intCast(length);
        for (0..count) |bits| for (0..2) |seed| {
            var input: [6]u8 = undefined;
            input[0] = @intCast(length);
            var expected: u8 = @intCast(seed);
            for (0..length) |i| {
                const value: u8 = @intCast((bits >> @intCast(i)) & 1);
                input[i + 1] = value;
                expected &= value;
            }
            input[length + 1] = @intCast(seed);
            var counts: [4]usize = undefined;
            for (images, &counts) |image, *steps| steps.* = try runSteps(image, input[0 .. length + 2], &.{expected});
            try std.testing.expect(counts[1] < counts[0]);
            cases += 1;
        };
    }
    std.debug.print("map/fold: {d} finite inputs, {d} executions; bytes {d}/{d}/{d}/{d}; {any}\n", .{ cases, cases * 4, images[0].len, images[1].len, images[2].len, images[3].len, compilation });
}
test "admitted swapped fold arguments change the answer and are rejected" {
    var candidate = (try data.sequence_fusion.construct(a, map_fold, .{})).?;
    defer candidate.deinit();
    var changed = candidate.program.blocks[0..11].*;
    changed[3].terminator.call.arguments = &.{ 7, 13 };
    var wrong = candidate.program;
    wrong.blocks = &changed;
    var admitted = try data.activation_ownership.analyze(a, wrong);
    admitted.deinit();
    try std.testing.expectError(error.InvalidSequenceFusion, data.sequence_fusion.validate(a, map_fold, wrong, candidate.sites, .{}));
    const bytes = try encoded(a, wrong);
    defer a.free(bytes);
    _ = try runSteps(bytes, &.{ 1, 1, 1 }, &.{0});
    const correct = try encoded(a, map_fold);
    defer a.free(correct);
    _ = try runSteps(correct, &.{ 1, 1, 1 }, &.{1});
}
test "eager mapper failure wins over an earlier possible folder failure" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try failingSteps(arena.allocator());
    var stats: data.sequence_fusion.Statistics = .{};
    var fused = try data.sequence_fusion.run(a, original, &stats, .{});
    defer fused.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.loops_fused);
    var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer compiled.deinit();
    for ([_]ir.Program{ original, fused.program, compiled.program }) |program| {
        const bytes = try encoded(a, program);
        defer a.free(bytes);
        var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{ 2, 0, 1, 1 } } });
        defer result.deinit();
        try std.testing.expect(result.record == .failed);
        try std.testing.expectEqualSlices(u8, &.{1}, result.record.failed.value);
    }
}
test "a genuinely possible intermediate capacity fault remains observable" {
    var program = map_fold;
    var schemas = map_fold.schemas[0..8].*;
    schemas[5].vector.maximum = 1;
    program.schemas = &schemas;
    var stats: data.sequence_fusion.Statistics = .{};
    var result = try data.sequence_fusion.run(a, program, &stats, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.loops_fused);
    for ([_]ir.Program{ program, result.program }) |arm| {
        const bytes = try encoded(a, arm);
        defer a.free(bytes);
        var execution = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{ 2, 1, 1, 1 } } });
        defer execution.deinit();
        try std.testing.expect(execution.record == .failed);
        try std.testing.expectEqualSlices(u8, &.{}, execution.record.failed.value);
    }
}

test "existing owning-element vectors and cleanup retain their admitted images" {
    const boundary = @import("boundary");
    var builder = boundary.source.Builder.init(a);
    defer builder.deinit();
    var original = try boundary.program.compile(a, try boundary.source.examples.borrowOperands(&builder));
    defer original.deinit();
    var owns_elements = false;
    for (original.program.schemas) |schema| if (schema == .vector) {
        const element = original.program.schemas[@intCast(schema.vector.element)];
        if (element == .internal and element.internal == .abstract_resource) owns_elements = true;
    };
    try std.testing.expect(owns_elements);
    var map_stats: data.sequence_fusion.Statistics = .{};
    var mapped = try data.sequence_fusion.run(a, original.program, &map_stats, .{});
    defer mapped.deinit();
    var unfold_stats: data.unfold_fusion.Statistics = .{};
    var unfolded = try data.unfold_fusion.run(a, original.program, &unfold_stats, .{});
    defer unfolded.deinit();
    try std.testing.expectEqual(@as(usize, 0), map_stats.loops_fused);
    try std.testing.expectEqual(@as(usize, 0), unfold_stats.protocols_fused);
    try std.testing.expect(!map_stats.work_limit and !unfold_stats.work_limit);
    const identity = try data.program_image.identity(a, original.program);
    try std.testing.expectEqual(identity, try data.program_image.identity(a, mapped.program));
    try std.testing.expectEqual(identity, try data.program_image.identity(a, unfolded.program));
}
