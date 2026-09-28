const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const pre = data.partial_redundancy;
const a = std.testing.allocator;
pub const diamond: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 2 },
    .schemas = &.{ .u64, .boolean, .unit },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 0, 0, 1, 1, 0, 0 } }, .result = 0 }},
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } }}, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 3, .when_true = .{ .block = 3 }, .when_false = .{ .block = 4 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 5, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 5 } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
    },
};
const Trace = struct { value: u64, evaluations: usize };
// Small independent interpreter for this fixture's actual emitted records.
// Edge sources are captured together before any destination is overwritten.
fn trace(program: ir.Program, inputs: [4]u64) !Trace {
    const function = program.functions[@intCast(program.roots.entry)];
    const values = try a.alloc(u64, function.layout.slots.len);
    defer a.free(values);
    @memset(values, 0);
    for (function.inputs, inputs) |slot, value| values[@intCast(slot)] = value;
    var block = function.entry;
    var count: usize = 0;
    for (0..100) |_| {
        const current = program.blocks[@intCast(block)];
        for (current.instructions) |op| switch (op.opcode) {
            .integer_bit_xor => {
                values[@intCast(op.destination)] = values[@intCast(op.operands[0])] ^ values[@intCast(op.operands[1])];
                count += 1;
            },
            .equal => {
                values[@intCast(op.destination)] = @intFromBool(values[@intCast(op.operands[0])] == values[@intCast(op.operands[1])]);
                count += 1;
            },
            .move => values[@intCast(op.destination)] = values[@intCast(op.operands[0])],
            else => return error.UnexpectedInstruction,
        };
        const edge = switch (current.terminator) {
            .return_value => |slot| return .{ .value = values[@intCast(slot)], .evaluations = count },
            .jump => |edge| edge,
            .branch => |branch| if (values[@intCast(branch.condition)] != 0) branch.when_true else branch.when_false,
            else => return error.UnexpectedTerminator,
        };
        const assigned = try a.alloc(u64, edge.assignments.len);
        defer a.free(assigned);
        for (edge.assignments, assigned) |assignment, *value| value.* = values[@intCast(assignment.source.slot)];
        for (edge.assignments, assigned) |assignment, value| values[@intCast(assignment.destination)] = value;
        block = edge.block;
    }
    return error.NoCompletion;
}
test "World executes PRE with one expression per join path and none on early return" {
    var optimized = try pre.run(a, diamond, null, .{});
    defer optimized.deinit();
    for ([_][2]u64{ .{ 1, 2 }, .{ 0, 0 }, .{ std.math.maxInt(u64), 42 } }) |words| {
        for ([_]bool{ false, true }) |first| for ([_]bool{ false, true }) |second| {
            const values: [4]u64 = .{ words[0], words[1], @intFromBool(first), @intFromBool(second) };
            const before = try trace(diamond, values);
            const after = try trace(optimized.program, values);
            try std.testing.expectEqual(before.value, after.value);
            try std.testing.expectEqual(@as(usize, if (first) 2 else if (second) 1 else 0), before.evaluations);
            try std.testing.expectEqual(@as(usize, if (first or second) 1 else 0), after.evaluations);
            var arguments: [18]u8 = undefined;
            std.mem.writeInt(u64, arguments[0..8], words[0], .little);
            std.mem.writeInt(u64, arguments[8..16], words[1], .little);
            arguments[16] = @intFromBool(first);
            arguments[17] = @intFromBool(second);
            for ([_]ir.Program{ diamond, optimized.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &arguments } });
                defer outcome.deinit();
                try std.testing.expect(outcome.record == .completed);
                try std.testing.expectEqual(after.value, std.mem.readInt(u64, outcome.record.completed[0..8], .little));
            }
        };
    }
}

pub fn liveDiamond() ir.Program {
    var program = diamond;
    program.roots.result = 1;
    program.functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 0, 0, 1, 1, 1, 1 } }, .result = 1 }};
    program.blocks = &.{
        diamond.blocks[0],
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .equal, .operands = &.{ 0, 1 } }}, .terminator = .{ .branch = .{ .condition = 4, .when_true = .{ .block = 3 }, .when_false = .{ .block = 4 } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 5, .opcode = .equal, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 5 } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
    };
    return program;
}
test "shared compilation and source-free linking select the live PRE diamond" {
    const original = comptime liveDiamond();
    var stats: data.closed_compilation.Statistics = .{};
    var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic, .statistics = &stats });
    defer compiled.deinit();
    try std.testing.expectEqual(.full, stats.selected_candidate);
    const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
    const object_bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(object_bytes);
    _ = try data.component.encode(a, object, object_bytes);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "pre", .object = object_bytes }}, &.{}, .{ .instance = "pre", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(object_bytes, 0xff);
    for ([_][2]u64{ .{ 1, 2 }, .{ 0, 0 }, .{ std.math.maxInt(u64), std.math.maxInt(u64) } }) |words| for ([_]bool{ false, true }) |first| for ([_]bool{ false, true }) |second| {
        const inputs: [4]u64 = .{ words[0], words[1], @intFromBool(first), @intFromBool(second) };
        const equal_words = words[0] == words[1];
        const expected = if (first and !equal_words) second else equal_words;
        const before = try trace(original, inputs);
        try std.testing.expectEqual(@as(usize, if (first and equal_words) 2 else 1), before.evaluations);
        var args: [18]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], words[0], .little);
        std.mem.writeInt(u64, args[8..16], words[1], .little);
        args[16] = @intFromBool(first);
        args[17] = @intFromBool(second);
        for ([_]ir.Program{ compiled.program, linked.program }) |program| {
            const after = try trace(program, inputs);
            try std.testing.expectEqual(@as(usize, 1), after.evaluations);
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer outcome.deinit();
            try std.testing.expect(outcome.record == .completed);
            try std.testing.expectEqualSlices(u8, &.{@intFromBool(expected)}, outcome.record.completed);
        }
    };
}
