const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const p = data.program;
const a = std.testing.allocator;
pub const repeated: ir.Program = blk: {
    @setEvalBranchQuota(10000);
    var slots: [53]p.Id = @splat(0);
    slots[2] = 1;
    var left: [25]ir.Instruction = undefined;
    var right: [25]ir.Instruction = undefined;
    left[0] = .{ .destination = 3, .opcode = .constant };
    right[0] = .{ .destination = 28, .opcode = .constant };
    for (1..25) |i| {
        const op: p.Opcode = switch ((i - 1) % 3) {
            0 => .integer_bit_xor,
            1 => .integer_bit_not,
            else => .integer_bit_or,
        };
        left[i] = .{ .destination = 3 + i, .opcode = op, .operands = if (op == .integer_bit_not) &.{2 + i} else &.{ if (i == 1) 0 else 2 + i, 3 } };
        right[i] = .{ .destination = 28 + i, .opcode = op, .operands = if (op == .integer_bit_not) &.{27 + i} else &.{ if (i == 1) 1 else 27 + i, 28 } };
    }
    const frozen_slots = slots;
    const frozen_left = left;
    const frozen_right = right;
    break :blk .{
        .roots = .{ .entry = 0, .result = 0, .failure = 0 },
        .schemas = &.{ .u64, .boolean },
        .constants = &.{.{ .schema = 0, .bytes = &.{ 0x15, 0x7c, 0x4a, 0x7f, 0xb9, 0x79, 0x37, 0x9e } }},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &frozen_slots }, .result = 0 }},
        .blocks = &.{
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
            .{ .function = 0, .instructions = &frozen_left, .terminator = .{ .return_value = 27 } },
            .{ .function = 0, .instructions = &frozen_right, .terminator = .{ .return_value = 52 } },
        },
    };
};

test "World executes one outlined worker through compilation and source-free linking" {
    var checked = try data.outlining.run(a, repeated, null, .{});
    defer checked.deinit();
    var statistics: data.closed_compilation.Statistics = .{};
    var compiled = try data.closed_compilation.run(a, repeated, .{ .contract = .semantic, .statistics = &statistics });
    defer compiled.deinit();
    try std.testing.expectEqual(.full, statistics.selected_candidate);
    const object: data.component.Object = .{ .program = repeated, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "outline", .object = encoded }}, &.{}, .{ .instance = "outline", .symbol = "main" }, .{ .contract = .semantic });
    defer linked.deinit();
    @memset(encoded, 0xff);
    for ([_][2]u64{ .{ 0, 1 }, .{ 7, 11 }, .{ std.math.maxInt(u64), 0 } }) |words| for ([_]bool{ false, true }) |branch| {
        var args: [17]u8 = undefined;
        std.mem.writeInt(u64, args[0..8], words[0], .little);
        std.mem.writeInt(u64, args[8..16], words[1], .little);
        args[16] = @intFromBool(branch);
        var expected = if (branch) words[0] else words[1];
        for (0..24) |i| switch (i % 3) {
            0 => expected ^= 0x9e3779b97f4a7c15,
            1 => expected = ~expected,
            else => expected |= 0x9e3779b97f4a7c15,
        };
        for ([_]ir.Program{ repeated, checked.program, compiled.program, linked.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer result.deinit();
            try std.testing.expect(result.record == .completed);
            try std.testing.expectEqual(expected, std.mem.readInt(u64, result.record.completed[0..8], .little));
        }
    };
}
