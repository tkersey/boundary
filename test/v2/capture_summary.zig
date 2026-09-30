const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const reused: ir.Program = .{
    .roots = .{ .entry = 0, .result = 3, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{0}, .use = .reusable } } }, .{ .product = &.{ 0, 0 } } },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 2, 0, 0, 3 } }, .result = 3 },
        .{ .entry = 3, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .computation, .operands = &.{ 0, 1 }, .immediate = 0 }}, .terminator = .{ .apply = .{ .computation = 4, .arguments = &.{2}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 4, .arguments = &.{3}, .next = .{ .block = 2, .assignments = &.{.{ .destination = 6, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 7, .opcode = .product, .operands = &.{ 5, 6 } }}, .terminator = .{ .return_value = 7 } },
        .{ .function = 1, .instructions = &.{ .{ .destination = 3, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } }, .{ .destination = 4, .opcode = .integer_bit_xor, .operands = &.{ 3, 2 } } }, .terminator = .{ .return_value = 4 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{ 0, 0 }, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 2 }},
};

fn fixture(a: std.mem.Allocator, calls: usize) !ir.Program {
    if (calls < 2 or calls > 256 or calls % 2 != 0) return error.InvalidCallCount;
    var program = reused;
    const functions = try a.dupe(ir.Function, reused.functions);
    functions[1].entry = calls + 1;
    const blocks = try a.alloc(ir.Block, calls + 2);
    for (blocks[0..calls], 0..) |*block, index| {
        block.* = .{ .function = 0, .instructions = if (index == 0) reused.blocks[0].instructions else &.{}, .terminator = .{ .apply = .{
            .computation = 4,
            .arguments = try a.dupe(u64, &.{if (index % 2 == 0) @as(u64, 2) else 3}),
            .next = .{ .block = index + 1, .assignments = try a.dupe(ir.Assignment, &.{.{ .destination = if (index % 2 == 0) 5 else 6, .source = .returned }}) },
        } } };
    }
    blocks[calls] = reused.blocks[2];
    blocks[calls + 1] = reused.blocks[3];
    program.functions = functions;
    program.blocks = blocks;
    return program;
}
fn inputBytes(values: [4]u64) [32]u8 {
    var args: [32]u8 = undefined;
    for (values, 0..) |value, index| std.mem.writeInt(u64, args[index * 8 ..][0..8], value, .little);
    return args;
}
fn expectedBytes(values: [4]u64) [16]u8 {
    var expected: [16]u8 = undefined;
    std.mem.writeInt(u64, expected[0..8], values[0] ^ values[1] ^ values[2], .little);
    std.mem.writeInt(u64, expected[8..16], values[0] ^ values[1] ^ values[3], .little);
    return expected;
}

// Emit paired immutable PKI3 inputs for World's existing replay-bench; no new
// benchmark runner or timing oracle. The expected digest is independently built.
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.MissingMode;
    const calls = try std.fmt.parseInt(usize, args.next() orelse "2", 10);
    if (args.next() != null) return error.UnexpectedArgument;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const values = [4]u64{ 0x12345678abcdef00, 0xa55aa55af00ff00f, 21, 99 };
    var storage: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &storage);
    if (std.mem.eql(u8, mode, "construction")) {
        const original = try fixture(a, calls);
        const Sample = struct { candidate: bool, ns: u64, allocations: usize, allocated_bytes: usize, retained_bytes: usize, image_bytes: usize };
        var samples: std.ArrayList(Sample) = .empty;
        for (0..12) |round| for (0..2) |position| {
            const candidate = (round + position) % 2 != 0;
            var meter = std.testing.FailingAllocator.init(init.gpa, .{});
            const start = std.Io.Clock.awake.now(init.io);
            var owned = if (candidate) try data.capture_summary.run(meter.allocator(), original, null, .{}) else try data.coalescing.run(meter.allocator(), original, .{});
            const elapsed: u64 = @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
            const row: Sample = .{ .candidate = candidate, .ns = elapsed, .allocations = meter.allocations, .allocated_bytes = meter.allocated_bytes, .retained_bytes = meter.allocated_bytes - meter.freed_bytes, .image_bytes = try data.program_image.encodedLength(owned.program) };
            owned.deinit();
            if (meter.allocated_bytes != meter.freed_bytes) return error.UnreleasedMeasuredStorage;
            if (round >= 3) try samples.append(a, row);
        };
        try std.json.Stringify.value(.{ .calls = calls, .samples = samples.items }, .{}, &out.interface);
        try out.interface.writeByte('\n');
    } else if (std.mem.eql(u8, mode, "expected")) {
        const expected = expectedBytes(values);
        const record: data.invocation.Outcome = .{ .completed = &expected };
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
            candidate = try data.capture_summary.run(a, baseline.program, null, .{});
            break :blk candidate.?.program;
        } else return error.InvalidMode;
        const image = try a.alloc(u8, try data.program_image.encodedLength(program));
        _ = try data.program_image.encode(a, program, image);
        const inputs = inputBytes(values);
        const invocation: data.invocation.Input = .{ .image = image, .instance = .{ .initial_args = &inputs } };
        const encoded = try a.alloc(u8, try data.invocation.encodedLength(data.invocation.Input, invocation));
        _ = try data.invocation.encode(data.invocation.Input, a, invocation, encoded);
        try out.interface.writeAll(encoded);
    }
    try out.interface.flush();
}

test "source-free XOR summary preserves repeated calls and shrinks retained environment" {
    const a = std.testing.allocator;
    const object: data.component.Object = .{ .program = reused, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
    const object_bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(object_bytes);
    _ = try data.component.encode(a, object, object_bytes);
    var linked = try data.linker.link(a, &.{.{ .key = "xor", .object = object_bytes }}, &.{}, .{ .instance = "xor", .symbol = "main" });
    defer linked.deinit();
    @memset(object_bytes, 0xff);
    var stats: data.capture_summary.Statistics = .{};
    var reduced = try data.capture_summary.run(a, linked.program, &stats, .{});
    defer reduced.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.fields_removed);
    var checkpoints: [2]usize = undefined;
    var payload: [2]usize = @splat(0);
    for ([_][4]u64{ .{ 5, 3, 21, 99 }, .{ 0, 0xffffffffffffffff, 42, 17 }, .{ 0x12345678abcdef00, 0xa55aa55af00ff00f, 0, 999 } }, 0..) |values, case| {
        const inputs = inputBytes(values);
        const expected = expectedBytes(values);
        for ([_]ir.Program{ linked.program, reduced.program }, 0..) |program, index| {
            const image = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(image);
            _ = try data.program_image.encode(a, program, image);
            const entry = program.functions[@intCast(program.roots.entry)].entry;
            const steps = program.blocks[@intCast(entry)].instructions.len;
            var paused = try world.invocation.invoke(a, .{ .image = image, .instance = .{ .initial_args = &inputs }, .quantum = steps });
            defer paused.deinit();
            try std.testing.expect(paused.record == .progressed and paused.record.progressed != null);
            const checkpoint = paused.record.progressed.?;
            if (case == 0) {
                checkpoints[index] = checkpoint.len;
                var graph = try data.state_image.decodeGraph(a, checkpoint);
                defer graph.deinit();
                for (graph.state.nodes) |node| if (node.record == .computation) {
                    const env = graph.state.nodes[@intCast(node.record.computation.environment.id)].record.environment;
                    for (env.values) |value| {
                        try std.testing.expect(value.body == .scalar);
                        payload[index] += value.body.scalar.len;
                    }
                };
            }
            var outcome = try world.invocation.invoke(a, .{ .image = image, .instance = .{ .state = checkpoint } });
            defer outcome.deinit();
            try std.testing.expect(outcome.record == .completed);
            try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
        }
    }
    try std.testing.expectEqual(@as(usize, 16), payload[0]);
    try std.testing.expectEqual(@as(usize, 8), payload[1]);
    try std.testing.expect(checkpoints[1] < checkpoints[0]);
    std.debug.print("XOR summary retained scalar payload {d}->{d}, checkpoint bytes {d}->{d}\n", .{ payload[0], payload[1], checkpoints[0], checkpoints[1] });
}
