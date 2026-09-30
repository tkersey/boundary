const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;
pub const unfold: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .boolean, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{}, .result = 3, .capture_bound = &.{0}, .use = .reusable } } }, .{ .product = &.{ 0, 2 } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 3, 0, 2, 0 } }, .result = 0 },
        .{ .entry = 4, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 2, 3 } }, .result = 3 },
        .{ .entry = 5, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0, 3 } }, .result = 3 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{0}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{
            .{ .destination = 3, .opcode = .field, .operands = &.{2}, .immediate = 0 },
            .{ .destination = 4, .opcode = .field, .operands = &.{2}, .immediate = 1 },
            .{ .destination = 5, .opcode = .boolean_not, .operands = &.{1} },
            .{ .destination = 1, .opcode = .select, .operands = &.{ 3, 5, 1 } },
        }, .terminator = .{ .branch = .{ .condition = 3, .when_true = .{ .block = 2 }, .when_false = .{ .block = 3 } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 4, .arguments = &.{}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{ .{ .destination = 1, .opcode = .computation, .operands = &.{0}, .immediate = 0 }, .{ .destination = 2, .opcode = .product, .operands = &.{ 0, 1 } } }, .terminator = .{ .return_value = 2 } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 0, .when_true = .{ .block = 6 }, .when_false = .{ .block = 7 } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .jump = .{ .block = 6 } } },
        .{ .function = 2, .instructions = &.{.{ .destination = 1, .opcode = .boolean_not, .operands = &.{0} }}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{1}, .next = .{ .block = 8, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
    },
    .constructors = &.{.{ .function = 2, .capture = 0, .schema = 2 }},
    .scopes = .{ .captures = &.{.{ .fields = &.{0}, .use = .reusable }} },
};

fn image(program: ir.Program) ![]u8 {
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
    errdefer a.free(bytes);
    _ = try data.program_image.encode(a, program, bytes);
    return bytes;
}
fn steps(program: ir.Program, input: []const u8, expected: u8) !usize {
    const bytes = try image(program);
    defer a.free(bytes);
    var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = input }, .quantum = 1 });
    defer result.deinit();
    var count: usize = 1;
    while (result.record == .progressed) {
        try std.testing.expect(count < 128);
        const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = result.record.progressed.? }, .quantum = 1 });
        result.deinit();
        result = next;
        count += 1;
    }
    try std.testing.expect(result.record == .completed);
    try std.testing.expectEqualSlices(u8, &.{expected}, result.record.completed);
    return count;
}
test "finite unfold/fold and early stop never invoke the unused divergent successor" {
    var baseline = try data.closed_compilation.run(a, unfold, .{});
    defer baseline.deinit();
    var checked = try data.unfold_fusion.run(a, unfold, null, .{});
    defer checked.deinit();
    var compiled = try data.closed_compilation.run(a, unfold, .{ .contract = .semantic });
    defer compiled.deinit();
    const object: data.component.Object = .{ .program = unfold, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 } } };
    const bmo = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(bmo);
    _ = try data.component.encode(a, object, bmo);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "unfold", .object = bmo }}, &.{}, .{ .instance = "unfold", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(bmo, 0xff);
    for ([_]ir.Program{ checked.program, compiled.program, linked.program }) |program| for (program.blocks) |block| {
        try std.testing.expect(block.terminator != .apply);
        for (block.instructions) |op| try std.testing.expect(op.opcode != .computation);
    };
    for (0..2) |initial| for (0..2) |seed| {
        const input = [_]u8{ @intCast(initial), @intCast(seed) };
        var counts: [4]usize = undefined;
        for ([_]ir.Program{ baseline.program, checked.program, compiled.program, linked.program }, &counts) |program, *count| count.* = try steps(program, &input, @intCast(1 - seed));
        try std.testing.expect(counts[2] < counts[0]);
        std.debug.print("unfold initial={d} seed={d}: steps {any}\n", .{ initial, seed, counts });
    };
}
test "an admitted eager-successor mutation diverges where the original consumer stops" {
    var candidate = (try data.unfold_fusion.construct(a, unfold, .{})).?;
    defer candidate.deinit();
    var blocks = candidate.program.blocks[0..9].*;
    blocks[1].terminator = .{ .call = .{ .function = 2, .arguments = &.{4}, .next = .{ .block = 2 } } };
    var forged = candidate.program;
    forged.blocks = &blocks;
    var admitted = try data.activation_ownership.analyze(a, forged);
    admitted.deinit();
    try std.testing.expectError(error.InvalidUnfoldFusion, data.unfold_fusion.validate(a, unfold, forged, .{}));
    _ = try steps(unfold, &.{ 1, 0 }, 1);
    const bytes = try image(forged);
    defer a.free(bytes);
    var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{ 1, 0 } }, .quantum = 64 });
    defer result.deinit();
    try std.testing.expect(result.record == .progressed);
}
test "an unbounded productive unfold preserves continued demand and same-image interruption" {
    var original = unfold;
    var blocks = unfold.blocks[0..9].*;
    blocks[7].instructions = &.{.{ .destination = 1, .opcode = .move, .operands = &.{0} }};
    original.blocks = &blocks;
    var stats: data.unfold_fusion.Statistics = .{};
    var checked = try data.unfold_fusion.run(a, original, &stats, .{});
    defer checked.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.protocols_fused);
    var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer compiled.deinit();
    for ([_]ir.Program{ original, checked.program, compiled.program }) |program| {
        const bytes = try image(program);
        defer a.free(bytes);
        var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{ 0, 1 } }, .quantum = 64 });
        defer result.deinit();
        for (0..4) |_| {
            try std.testing.expect(result.record == .progressed);
            const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = result.record.progressed.? }, .quantum = 64 });
            result.deinit();
            result = next;
        }
        try std.testing.expect(result.record == .progressed);
    }
}
