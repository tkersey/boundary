const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const reused: ir.Program = .{
    .roots = .{ .entry = 0, .result = 3, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{3}, .use = .reusable } } }, .{ .product = &.{ 0, 0 } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 3, 0, 0, 2, 0, 0, 3 } }, .result = 3 },
        .{ .entry = 3, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 3, 0, 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .computation, .operands = &.{0}, .immediate = 0 }}, .terminator = .{ .apply = .{ .computation = 3, .arguments = &.{1}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 3, .arguments = &.{2}, .next = .{ .block = 2, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 6, .opcode = .product, .operands = &.{ 4, 5 } }}, .terminator = .{ .return_value = 6 } },
        .{ .function = 1, .instructions = &.{ .{ .destination = 2, .opcode = .field, .operands = &.{0}, .immediate = 0 }, .{ .destination = 3, .opcode = .integer_bit_xor, .operands = &.{ 2, 1 } } }, .terminator = .{ .return_value = 3 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{3}, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 2 }},
};

const large: ir.Program = blk: {
    var program = reused;
    program.schemas = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{5}, .use = .reusable } } }, reused.schemas[3], .{ .array = .{ .element = 6, .length = 4096 } }, .{ .product = &.{ 0, 4 } }, .u8 };
    program.functions = &.{ .{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 5, 0, 0, 2, 0, 0, 3 } }, .result = 3 }, .{ .entry = 3, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 5, 0, 0, 0 } }, .result = 0 } };
    program.scopes.captures = &.{.{ .fields = &.{5}, .use = .reusable }};
    break :blk program;
};
fn fixture(a: std.mem.Allocator, calls: usize) !ir.Program {
    if (calls < 2 or calls > 256 or calls % 2 != 0) return error.InvalidCallCount;
    var program = large;
    const functions = try a.dupe(ir.Function, large.functions);
    functions[1].entry = calls + 1;
    const blocks = try a.alloc(ir.Block, calls + 2);
    for (blocks[0..calls], 0..) |*block, index| block.* = .{ .function = 0, .instructions = if (index == 0) large.blocks[0].instructions else &.{}, .terminator = .{ .apply = .{ .computation = 3, .arguments = try a.dupe(u64, &.{if (index % 2 == 0) @as(u64, 1) else 2}), .next = .{ .block = index + 1, .assignments = try a.dupe(ir.Assignment, &.{.{ .destination = if (index % 2 == 0) 4 else 5, .source = .returned }}) } } } };
    blocks[calls] = large.blocks[2];
    blocks[calls + 1] = large.blocks[3];
    program.functions = functions;
    program.blocks = blocks;
    return program;
}
fn inputs(value: u64) [4120]u8 {
    var result: [4120]u8 = @splat(0xa5);
    std.mem.writeInt(u64, result[0..8], value, .little);
    std.mem.writeInt(u64, result[4104..4112], 21, .little);
    std.mem.writeInt(u64, result[4112..4120], 99, .little);
    return result;
}
fn expected(value: u64) [16]u8 {
    var result: [16]u8 = undefined;
    std.mem.writeInt(u64, result[0..8], value ^ 21, .little);
    std.mem.writeInt(u64, result[8..16], value ^ 99, .little);
    return result;
}

// Paired PKI3 inputs for World's existing replay-bench, with an independent oracle.
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.MissingMode;
    const calls = try std.fmt.parseInt(usize, args.next() orelse "2", 10);
    if (args.next() != null) return error.UnexpectedArgument;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    if (std.mem.eql(u8, mode, "expected")) {
        const value = expected(0x12345678abcdef00);
        const record: data.invocation.Outcome = .{ .completed = &value };
        const encoded = try a.alloc(u8, try data.invocation.encodedLength(data.invocation.Outcome, record));
        _ = try data.invocation.encode(data.invocation.Outcome, a, record, encoded);
        const digest = std.fmt.bytesToHex(data.wire.digest(encoded), .lower);
        try out.interface.writeAll(&digest);
        try out.interface.writeByte('\n');
    } else {
        var baseline = try data.coalescing.run(a, try fixture(a, calls), .{});
        defer baseline.deinit();
        var candidate: ?data.coalescing.Owned = null;
        defer if (candidate) |*owner| owner.deinit();
        const program = if (std.mem.eql(u8, mode, "baseline")) baseline.program else if (std.mem.eql(u8, mode, "candidate")) blk: {
            candidate = try data.capture_projection.run(a, baseline.program, null, .{});
            break :blk candidate.?.program;
        } else return error.InvalidMode;
        const image = try a.alloc(u8, try data.program_image.encodedLength(program));
        _ = try data.program_image.encode(a, program, image);
        const input = inputs(0x12345678abcdef00);
        const invocation: data.invocation.Input = .{ .image = image, .instance = .{ .initial_args = &input } };
        const encoded = try a.alloc(u8, try data.invocation.encodedLength(data.invocation.Input, invocation));
        _ = try data.invocation.encode(data.invocation.Input, a, invocation, encoded);
        try out.interface.writeAll(encoded);
    }
    try out.interface.flush();
}

test "source-free field capture releases unobserved payload and preserves reused-call results" {
    const a = std.testing.allocator;
    const object: data.component.Object = .{ .program = large, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
    const object_bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(object_bytes);
    _ = try data.component.encode(a, object, object_bytes);
    var linked = try data.linker.link(a, &.{.{ .key = "projection", .object = object_bytes }}, &.{}, .{ .instance = "projection", .symbol = "main" });
    defer linked.deinit();
    @memset(object_bytes, 0xff);
    var stats: data.capture_projection.Statistics = .{};
    var reduced = try data.capture_projection.run(a, linked.program, &stats, .{});
    defer reduced.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.constructors_projected);
    var checkpoints: [2]usize = undefined;
    var blobs: [2]usize = @splat(0);
    for ([_]u64{ 10, 0xffffffffffffffff, 0x12345678abcdef00 }, 0..) |value, case| {
        const arguments = inputs(value);
        const answer = expected(value);
        for ([_]ir.Program{ linked.program, reduced.program }, 0..) |program, index| {
            const image = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(image);
            _ = try data.program_image.encode(a, program, image);
            const entry = program.functions[@intCast(program.roots.entry)].entry;
            var paused = try world.invocation.invoke(a, .{ .image = image, .instance = .{ .initial_args = &arguments }, .quantum = program.blocks[@intCast(entry)].instructions.len });
            defer paused.deinit();
            try std.testing.expect(paused.record == .progressed and paused.record.progressed != null);
            const state = paused.record.progressed.?;
            if (case == 0) {
                checkpoints[index] = state.len;
                var graph = try data.state_image.decodeGraph(a, state);
                defer graph.deinit();
                for (graph.state.blobs) |blob| blobs[index] += blob.bytes.len;
            }
            var result = try world.invocation.invoke(a, .{ .image = image, .instance = .{ .state = state } });
            defer result.deinit();
            try std.testing.expect(result.record == .completed);
            try std.testing.expectEqualSlices(u8, &answer, result.record.completed);
        }
    }
    try std.testing.expect(blobs[0] >= 4096);
    try std.testing.expectEqual(@as(usize, 0), blobs[1]);
    try std.testing.expect(checkpoints[1] < checkpoints[0]);
    std.debug.print("capture projection retained blob bytes {d}->{d}, checkpoint bytes {d}->{d}\n", .{ blobs[0], blobs[1], checkpoints[0], checkpoints[1] });
}

test "projection preserves a product field still observed by the parent" {
    const a = std.testing.allocator;
    var original = reused;
    var functions = reused.functions[0..2].*;
    functions[0].layout.slots = &.{ 3, 0, 0, 2, 0, 0, 3, 0 };
    original.functions = &functions;
    var blocks = reused.blocks[0..4].*;
    blocks[2].instructions = &.{ .{ .destination = 7, .opcode = .field, .operands = &.{0}, .immediate = 1 }, .{ .destination = 4, .opcode = .integer_bit_xor, .operands = &.{ 4, 7 } }, reused.blocks[2].instructions[0] };
    original.blocks = &blocks;
    var reduced = try data.capture_projection.run(a, original, null, .{});
    defer reduced.deinit();
    var arguments: [32]u8 = undefined;
    for ([_]u64{ 10, 77, 21, 99 }, 0..) |value, index| std.mem.writeInt(u64, arguments[index * 8 ..][0..8], value, .little);
    var answer: [16]u8 = undefined;
    std.mem.writeInt(u64, answer[0..8], 10 ^ 21 ^ 77, .little);
    std.mem.writeInt(u64, answer[8..16], 10 ^ 99, .little);
    for ([_]ir.Program{ original, reduced.program }) |program| {
        const image = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(image);
        _ = try data.program_image.encode(a, program, image);
        var result = try world.invocation.invoke(a, .{ .image = image, .instance = .{ .initial_args = &arguments } });
        defer result.deinit();
        try std.testing.expect(result.record == .completed);
        try std.testing.expectEqualSlices(u8, &answer, result.record.completed);
    }
}

test "failing variant extraction stays after closure construction" {
    const a = std.testing.allocator;
    var original = reused;
    original.schemas = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{4}, .use = .reusable } } }, reused.schemas[3], .{ .sum = &.{ 0, 0 } } };
    original.constants = &.{.{ .schema = 1, .bytes = &.{} }};
    original.functions = &.{ .{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 4, 0, 0, 2, 0, 0, 3 } }, .result = 3 }, .{ .entry = 3, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 4, 0, 0, 0 } }, .result = 0 } };
    original.scopes.captures = &.{.{ .fields = &.{4}, .use = .reusable }};
    var blocks = reused.blocks[0..4].*;
    blocks[3].instructions = &.{ .{ .destination = 2, .opcode = .variant_payload, .operands = &.{0}, .immediate = 0, .failures = &.{.{ .kind = .invalid_variant, .value = 0 }} }, reused.blocks[3].instructions[1] };
    original.blocks = &blocks;
    var reduced = try data.capture_projection.run(a, original, null, .{});
    defer reduced.deinit();
    var arguments: [25]u8 = @splat(0);
    arguments[0] = 1;
    std.mem.writeInt(u64, arguments[1..9], 7, .little);
    std.mem.writeInt(u64, arguments[9..17], 21, .little);
    std.mem.writeInt(u64, arguments[17..25], 99, .little);
    for ([_]ir.Program{ original, reduced.program }) |program| {
        const image = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(image);
        _ = try data.program_image.encode(a, program, image);
        var paused = try world.invocation.invoke(a, .{ .image = image, .instance = .{ .initial_args = &arguments }, .quantum = 1 });
        defer paused.deinit();
        try std.testing.expect(paused.record == .progressed and paused.record.progressed != null);
        var result = try world.invocation.invoke(a, .{ .image = image, .instance = .{ .state = paused.record.progressed.? } });
        defer result.deinit();
        try std.testing.expect(result.record == .failed);
        try std.testing.expectEqualSlices(u8, &.{}, result.record.failed.value);
    }
}
