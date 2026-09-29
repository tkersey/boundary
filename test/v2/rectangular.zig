const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const p = data.program;
const a = std.testing.allocator;
pub const base: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .boolean },
    .effects = &.{},
    .constants = &.{ .{ .schema = 0, .bytes = &.{ 8, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 2, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 1, .bytes = &.{} } },
    .functions = &.{.{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = &.{ 0, 0, 0, 0, 0, 0, 2, 0 } }, .result = 0 }},
    .blocks = &.{
        .{ .function = 0, .instructions = &.{ .{ .destination = 0, .opcode = .constant, .immediate = 0 }, .{ .destination = 1, .opcode = .constant, .immediate = 1 }, .{ .destination = 2, .opcode = .constant, .immediate = 2 }, .{ .destination = 4, .opcode = .constant, .immediate = 2 }, .{ .destination = 5, .opcode = .constant, .immediate = 3 } }, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 6, .opcode = .less, .operands = &.{ 2, 0 } }}, .terminator = .{ .branch = .{ .condition = 6, .when_true = .{ .block = 2 }, .when_false = .{ .block = 6 } } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .constant, .immediate = 2 }}, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 6, .opcode = .less, .operands = &.{ 3, 1 } }}, .terminator = .{ .branch = .{ .condition = 6, .when_true = .{ .block = 4 }, .when_false = .{ .block = 5 } } } },
        .{ .function = 0, .instructions = &.{ .{ .destination = 7, .opcode = .integer_bit_xor, .operands = &.{ 2, 3 } }, .{ .destination = 4, .opcode = .integer_bit_xor, .operands = &.{ 4, 7 } }, .{ .destination = 3, .opcode = .integer_add, .operands = &.{ 3, 5 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 4 }} } }, .terminator = .{ .jump = .{ .block = 3 } } },
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .integer_add, .operands = &.{ 2, 5 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 4 }} }}, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
    },
};
pub fn rectangle(allocator: std.mem.Allocator, rows: u64, columns: u64) !ir.Program {
    var result = base;
    const constants = try allocator.dupe(p.Literal, base.constants);
    for ([_]u64{ rows, columns }, 0..) |value, index| {
        const bytes = try allocator.alloc(u8, 8);
        std.mem.writeInt(u64, bytes[0..8], value, .little);
        constants[index].bytes = bytes;
    }
    result.constants = constants;
    return result;
}

fn execute(program: ir.Program, expected: u64) !usize {
    return executeWithVisits(program, expected, null);
}
fn executeWithVisits(program: ir.Program, expected: u64, domain: ?data.rectangular_loops.Shape) !usize {
    const visited = try a.alloc(bool, if (domain) |s| @intCast(s.rows * s.columns) else 0);
    defer a.free(visited);
    @memset(visited, false);
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
    defer a.free(bytes);
    _ = try data.program_image.encode(a, program, bytes);
    var session = try world.Session.initImage(a, bytes, &.{});
    defer session.deinit();
    var steps: usize = 0;
    while (steps < 10000) {
        if (domain) |s| if (session.roots.current) |current| {
            const node = try session.store.get(current);
            if (node == .control and node.control.block == 8) {
                const frame = try session.frames.get(current.id);
                if (frame.position == 0) {
                    const iv = try session.frames.slots.get(frame.view, @intCast(s.i));
                    const jv = try session.frames.slots.get(frame.view, @intCast(s.j));
                    const i = std.mem.readInt(u64, iv.body.scalar[0..8], .little);
                    const j = std.mem.readInt(u64, jv.body.scalar[0..8], .little);
                    try std.testing.expect(i < s.rows and j < s.columns);
                    const point: usize = @intCast(i * s.columns + j);
                    try std.testing.expect(!visited[point]);
                    visited[point] = true;
                }
            }
        };
        steps += 1;
        switch (try session.run(1)) {
            .progressed => {
                if (steps % 7 == 0) {
                    const checkpoint = try session.checkpoint(a);
                    defer a.free(checkpoint);
                    const restored = try world.Session.restoreImage(a, bytes, checkpoint);
                    session.deinit();
                    session = restored;
                }
            },
            .completed => |value| {
                for (visited) |present| try std.testing.expect(present);
                const result = try session.bytes(&value);
                try std.testing.expectEqual(expected, std.mem.readInt(u64, result[0..8], .little));
                return steps;
            },
            else => return error.UnexpectedOutcome,
        }
    }
    return error.StepLimit;
}
test "rectangular interchange exhausts small domains through shared and source-free compilation" {
    for (0..7) |rows| for (0..7) |columns| {
        var arena = std.heap.ArenaAllocator.init(a);
        defer arena.deinit();
        const original = try rectangle(arena.allocator(), rows, columns);
        var expected: u64 = 0;
        for (0..rows) |i| for (0..columns) |j| {
            expected ^= @as(u64, @intCast(i)) ^ @as(u64, @intCast(j));
        };
        const before = try execute(original, expected);
        try std.testing.expectEqual((try data.rectangular_loops.executionWork(a, original)).?, before);
        if (try data.rectangular_loops.construct(a, original, .{})) |value| {
            var candidate = value;
            defer candidate.deinit();
            try data.rectangular_loops.validate(a, original, candidate.program, candidate.shape, .{});
            const after = try execute(candidate.program, expected);
            try std.testing.expectEqual((try data.rectangular_loops.executionWork(a, candidate.program)).?, after);
            try std.testing.expect(after < before);
        }
        var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
        defer shared.deinit();
        _ = try execute(shared.program, expected);
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "rectangle", .object = encoded }}, &.{}, .{ .instance = "rectangle", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        _ = try execute(linked.program, expected);
    };
}

test "shared compilation selects the lower-control-work rectangular schedule" {
    var stats: data.closed_compilation.Statistics = .{};
    var shared = try data.closed_compilation.run(a, base, .{ .contract = .semantic, .statistics = &stats });
    defer shared.deinit();
    try std.testing.expectEqual(data.closed_compilation.Outcome.applied, stats.outcome);
    const steps = try execute(shared.program, 0);
    try std.testing.expect(steps < 169);
    std.debug.print("rectangle 8x2: original_steps=169 shared_steps={d} bytes={d}\n", .{ steps, try data.program_image.encodedLength(shared.program) });
}

test "tiled records cover partial rectangles and preserve structural step contracts" {
    for (0..10) |rows| for (0..10) |columns| {
        var arena = std.heap.ArenaAllocator.init(a);
        defer arena.deinit();
        const original = try rectangle(arena.allocator(), rows, columns);
        var expected: u64 = 0;
        for (0..rows) |i| for (0..columns) |j| {
            expected ^= @as(u64, @intCast(i)) ^ @as(u64, @intCast(j));
        };
        var tiled = (try data.rectangular_tiling.construct(a, original, .{})).?;
        defer tiled.deinit();
        try data.rectangular_tiling.validate(a, original, tiled.program, tiled.source, .{});
        const steps = try executeWithVisits(tiled.program, expected, tiled.source);
        try std.testing.expectEqual(data.rectangular_tiling.executionWork(tiled.source, original.blocks[tiled.source.body].instructions.len).?, steps);
    };
    var structural = try data.closed_compilation.run(a, base, .{ .contract = .structural });
    defer structural.deinit();
    try std.testing.expectEqual(@as(usize, 169), try execute(structural.program, 0));
}

test "the tiling cost guard can retain a cheaper empty-column schedule" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try rectangle(arena.allocator(), 20, 0);
    var stats: data.rectangular_tiling.Statistics = .{};
    var selected = try data.rectangular_tiling.run(a, original, &stats, .{});
    defer selected.deinit();
    try std.testing.expectEqual(@as(usize, 1), stats.tiled);
    try std.testing.expect(!stats.economic_rejection);
    try std.testing.expectEqual(@as(usize, 169), try execute(original, 0));
    try std.testing.expectEqual(@as(usize, 71), try execute(selected.program, 0));
}

pub fn aliasedRectangle(allocator: std.mem.Allocator) !ir.Program {
    var result = base;
    result.schemas = &.{ .u64, .unit, .boolean, .{ .internal = .{ .region = 0 } }, .{ .internal = .{ .cell = .{ .element = 0, .region = 0 } } }, .{ .internal = .{ .computation = .{ .parameters = &.{3}, .result = 0, .use = .reusable, .regions = &.{0} } } } };
    result.functions = &.{
        .{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = &.{ 5, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{8}, .layout = .{ .slots = &.{ 0, 0, 0, 0, 0, 0, 2, 0, 3, 4, 4, 1, 0 } }, .result = 0, .regions = &.{0} },
    };
    const blocks = try allocator.alloc(ir.Block, 9);
    blocks[0] = .{ .function = 0, .instructions = &.{.{ .destination = 0, .opcode = .computation, .immediate = 0 }}, .terminator = .{ .with_region = .{ .region = 0, .body = 0, .arguments = &.{}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 1, .source = .returned }} } } } };
    blocks[1] = .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 1 } };
    for (base.blocks, 0..) |source, id| {
        blocks[id + 2] = source;
        blocks[id + 2].function = 1;
        switch (blocks[id + 2].terminator) {
            .jump => |*edge| edge.block += 2,
            .branch => |*branch| {
                branch.when_true.block += 2;
                branch.when_false.block += 2;
            },
            else => {},
        }
    }
    const initial = try allocator.alloc(ir.Instruction, 7);
    @memcpy(initial[0..5], base.blocks[0].instructions);
    initial[5] = .{ .destination = 9, .opcode = .cell_new, .operands = &.{ 8, 4 } };
    initial[6] = .{ .destination = 10, .opcode = .move, .operands = &.{9} };
    blocks[2].instructions = initial;
    blocks[6].instructions = &.{
        .{ .destination = 7, .opcode = .cell_get, .operands = &.{9} },
        .{ .destination = 4, .opcode = .integer_bit_xor, .operands = &.{ 4, 7 } },
        .{ .destination = 12, .opcode = .integer_bit_xor, .operands = &.{ 2, 3 } },
        .{ .destination = 12, .opcode = .integer_bit_or, .operands = &.{ 12, 7 } },
        .{ .destination = 11, .opcode = .cell_set, .operands = &.{ 10, 12 } },
        base.blocks[4].instructions[2],
    };
    result.blocks = blocks;
    result.scopes = .{ .region_count = 1, .captures = &.{.{ .fields = &.{}, .use = .reusable }} };
    result.constructors = &.{.{ .function = 1, .capture = 0, .schema = 5 }};
    return result;
}

test "mutable alias iteration retains its ordered observations" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try aliasedRectangle(arena.allocator());
    try std.testing.expect(try data.rectangular_loops.construct(a, original, .{}) == null);
    try std.testing.expect(try data.rectangular_tiling.construct(a, original, .{}) == null);
    var cell: u64 = 0;
    var expected: u64 = 0;
    for (0..8) |i| for (0..2) |j| {
        expected ^= cell;
        cell |= @as(u64, @intCast(i)) ^ @as(u64, @intCast(j));
    };
    _ = try execute(original, expected);
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer shared.deinit();
    _ = try execute(shared.program, expected);
}

test "refusing checked body arithmetic preserves which failure occurs first" {
    var original = base;
    original.roots.failure = 0;
    original.constants = &.{ base.constants[0], base.constants[1], base.constants[2], base.constants[3], .{ .schema = 0, .bytes = &.{ 11, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 22, 0, 0, 0, 0, 0, 0, 0 } } };
    var functions = base.functions[0..1].*;
    functions[0].layout.slots = &.{ 0, 0, 0, 0, 0, 0, 2, 0, 0 };
    original.functions = &functions;
    var blocks = base.blocks[0..7].*;
    var work = [_]ir.Instruction{
        .{ .destination = 7, .opcode = .integer_sub, .operands = &.{ 2, 3 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 4 }} },
        .{ .destination = 8, .opcode = .integer_sub, .operands = &.{ 3, 2 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 5 }} },
        base.blocks[4].instructions[1],
        base.blocks[4].instructions[2],
    };
    blocks[4].instructions = &work;
    original.blocks = &blocks;
    try std.testing.expect(try data.rectangular_loops.construct(a, original, .{}) == null);
    try std.testing.expect(try data.rectangular_tiling.construct(a, original, .{}) == null);
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer shared.deinit();
    // Independently force the otherwise valid pure control permutation to
    // demonstrate why the totality gate matters for this admitted near-example.
    var pure = (try data.rectangular_loops.construct(a, base, .{})).?;
    defer pure.deinit();
    var reordered = blocks;
    for ([_]usize{ 0, 1, 2, 3, 5 }) |id| reordered[id] = pure.program.blocks[id];
    var reordered_work = work;
    reordered_work[3] = pure.program.blocks[4].instructions[2];
    reordered[4].instructions = &reordered_work;
    var wrong = original;
    wrong.blocks = &reordered;
    for ([_]ir.Program{ original, shared.program, wrong }, 0..) |program, index| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{} } });
        defer result.deinit();
        try std.testing.expect(result.record == .failed);
        try std.testing.expectEqual(@as(u64, if (index == 2) 22 else 11), std.mem.readInt(u64, result.record.failed.value[0..8], .little));
    }
}
