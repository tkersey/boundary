const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const boundary = @import("boundary");
const ir = data.activation;
const a = std.testing.allocator;
pub const xor_chain: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit, .{ .vector = .{ .element = 0, .maximum = 4096 } }, .{ .product = &.{ 0, 2 } }, .{ .sum = &.{ 1, 3 } } },
    .constants = &.{.{ .schema = 1, .bytes = &.{} }},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 2, 0, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 2, 0, 4, 3, 0, 2, 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 1 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 2, .opcode = .sequence_pop, .operands = &.{0} }}, .terminator = .{ .switch_variant = .{ .value = 2, .cases = &.{ .{ .block = 3 }, .{ .block = 4 } } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
        .{ .function = 1, .instructions = &.{
            .{ .destination = 3, .opcode = .variant_payload, .operands = &.{2}, .immediate = 1, .failures = &.{.{ .kind = .invalid_variant, .value = 0 }} },
            .{ .destination = 4, .opcode = .field, .operands = &.{3}, .immediate = 0 },
            .{ .destination = 5, .opcode = .field, .operands = &.{3}, .immediate = 1 },
        }, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 5, 1 }, .next = .{ .block = 5, .assignments = &.{.{ .destination = 6, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 7, .opcode = .integer_bit_xor, .operands = &.{ 4, 6 } }}, .terminator = .{ .return_value = 7 } },
    },
};
pub fn booleanChain(allocator: std.mem.Allocator) !ir.Program {
    var program = xor_chain;
    program.schemas = &.{ .boolean, .unit, .{ .vector = .{ .element = 5, .maximum = 4096 } }, .{ .product = &.{ 5, 2 } }, .{ .sum = &.{ 1, 3 } }, .{ .product = &.{ 0, 0 } } };
    const functions = try allocator.dupe(ir.Function, program.functions);
    functions[1].layout.slots = &.{ 2, 0, 4, 3, 5, 2, 0, 0, 0, 0 };
    program.functions = functions;
    const blocks = try allocator.dupe(ir.Block, program.blocks);
    blocks[5].instructions = &.{
        .{ .destination = 8, .opcode = .field, .operands = &.{4}, .immediate = 0 },
        .{ .destination = 9, .opcode = .field, .operands = &.{4}, .immediate = 1 },
        .{ .destination = 7, .opcode = .select, .operands = &.{ 6, 9, 8 } },
    };
    program.blocks = blocks;
    return program;
}

pub fn generated(b: *boundary.source.Builder) !boundary.source.Module {
    const integer = try b.scalar(u64);
    const unit = try b.scalar(void);
    const sequence = try b.schema(.{ .vector = .{ .element = integer, .maximum = 4096 } });
    const pair = try b.schema(.{ .product = &.{ integer, sequence } });
    const optional = try b.schema(.{ .sum = &.{ unit, pair } });
    const worker = try b.declare(&.{ sequence, integer }, integer, &.{}, &.{});
    const item = try b.variable(pair);
    const mask = try b.variable(integer);
    const tail = try b.variable(sequence);
    const answer = try b.variable(integer);
    const popped = try b.variable(optional);
    const seed = try b.reference(b.parameter(worker, 1));
    const recurse = try b.term(.{ .call = .{ .function = worker, .arguments = &.{ try b.reference(tail), seed } } });
    const action = try b.pure(try b.primitive(integer, .integer_bit_xor, &.{ try b.reference(mask), try b.reference(answer) }, 0));
    const more = try b.bind(mask, try b.pure(try b.primitive(integer, .field, &.{try b.reference(item)}, 0)), try b.bind(tail, try b.pure(try b.primitive(sequence, .field, &.{try b.reference(item)}, 1)), try b.bind(answer, recurse, action)));
    const choose = try b.term(.{ .match_sum = .{ .value = try b.reference(popped), .cases = &.{ .{ .variable = try b.variable(unit), .body = try b.pure(seed) }, .{ .variable = item, .body = more } } } });
    try b.define(worker, try b.bind(popped, try b.pure(try b.primitive(optional, .sequence_pop, &.{try b.reference(b.parameter(worker, 0))}, 0)), choose));
    const main = try b.declare(&.{ sequence, integer }, integer, &.{}, &.{});
    try b.define(main, try b.term(.{ .call = .{ .function = worker, .arguments = &.{ try b.reference(b.parameter(main, 0)), try b.reference(b.parameter(main, 1)) } } }));
    return b.module(main, unit);
}
fn image(program: ir.Program) ![]u8 {
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
    errdefer a.free(bytes);
    _ = try data.program_image.encode(a, program, bytes);
    return bytes;
}
const Observation = struct { steps: usize, continuations: usize, activation_bindings: usize, checkpoint_bytes: usize };
fn run(program: ir.Program, input: []const u8, expected: []const u8) !Observation {
    const bytes = try image(program);
    defer a.free(bytes);
    var session = try world.Session.initImage(a, bytes, input);
    defer session.deinit();
    var frames: usize = 0;
    var bindings: usize = 0;
    var checkpoint_len: usize = 0;
    var sampled = false;
    var steps: usize = 0;
    while (true) {
        try std.testing.expect(steps < 200000);
        if (!sampled) if (session.roots.current) |current| {
            const node = try session.store.get(current);
            if (node == .control and program.blocks[@intCast(node.control.block)].terminator == .return_value) {
                const checkpoint = try session.checkpoint(a);
                defer a.free(checkpoint);
                checkpoint_len = checkpoint.len;
                var graph = try data.state_image.decodeGraph(a, checkpoint);
                defer graph.deinit();
                for (graph.state.nodes) |n| {
                    frames += @intFromBool(n.record == .continuation);
                    if (n.activation) |activation| bindings += activation.bindings.len;
                }
                const restored = try world.Session.restoreImage(a, bytes, checkpoint);
                session.deinit();
                session = restored;
                sampled = true;
            }
        };
        const out = try session.run(1);
        steps += 1;
        switch (out) {
            .progressed => {},
            .completed => |value| {
                try std.testing.expectEqualSlices(u8, expected, try session.bytes(&value));
                break;
            },
            else => return error.UnexpectedOutcome,
        }
    }
    try std.testing.expect(sampled);
    return .{ .steps = steps, .continuations = frames, .activation_bindings = bindings, .checkpoint_bytes = checkpoint_len };
}
test "runtime-length XOR chains retain one summarized context at 1 16 256 and 4096 masks" {
    var baseline = try data.closed_compilation.run(a, xor_chain, .{});
    defer baseline.deinit();
    var compressed = try data.context_compression.run(a, xor_chain, null, .{});
    defer compressed.deinit();
    var shared = try data.closed_compilation.run(a, xor_chain, .{ .contract = .semantic });
    defer shared.deinit();
    var linked = try linkOriginal(xor_chain);
    defer linked.deinit();
    for ([_]usize{ 1, 16, 256, 4096 }) |n| {
        var input = try a.alloc(u8, n * 8 + 18);
        defer a.free(input);
        var writer: data.wire.Writer = .{ .output = input };
        try writer.natural(n);
        var expected: u64 = 0x123456789abcdef0;
        for (0..n) |i| {
            const value = @as(u64, @intCast(i)) *% 0x9e3779b97f4a7c15;
            std.mem.writeInt(u64, input[writer.position..][0..8], value, .little);
            writer.position += 8;
            expected ^= value;
        }
        std.mem.writeInt(u64, input[writer.position..][0..8], 0x123456789abcdef0, .little);
        writer.position += 8;
        var answer: [8]u8 = undefined;
        std.mem.writeInt(u64, &answer, expected, .little);
        const before = try run(baseline.program, input[0..writer.position], &answer);
        const after = try run(compressed.program, input[0..writer.position], &answer);
        const integrated = try run(shared.program, input[0..writer.position], &answer);
        const source_free = try run(linked.program, input[0..writer.position], &answer);
        try std.testing.expect(before.continuations >= n);
        try std.testing.expect(after.continuations <= 1);
        try std.testing.expect(integrated.continuations <= 1);
        try std.testing.expect(source_free.continuations <= 1);
        try std.testing.expect(after.activation_bindings <= 4);
        std.debug.print("XOR n={d} baseline={any} checked={any} shared={any}\n", .{ n, before, after, integrated });
    }
}
test "ordinary source recursive lowering is recognized without authoring API changes" {
    var b = boundary.source.Builder.init(a);
    defer b.deinit();
    var original = try boundary.program.compile(a, try generated(&b));
    defer original.deinit();
    var stats: data.context_compression.Statistics = .{};
    var checked = try data.context_compression.run(a, original.program, &stats, .{});
    defer checked.deinit();
    if (stats.contexts_compressed == 0) {
        for (original.program.functions, 0..) |function, id| std.debug.print("function {d}: {any}\n", .{ id, function });
        for (original.program.blocks, 0..) |block, id| std.debug.print("block {d}: {any}\n", .{ id, block });
    }
    try std.testing.expectEqual(@as(usize, 1), stats.contexts_compressed);
    var input: [33]u8 = undefined;
    input[0] = 3;
    for ([_]u64{ 1, 2, 3, 9 }, 0..) |v, i| std.mem.writeInt(u64, input[1 + i * 8 ..][0..8], v, .little);
    _ = try run(checked.program, &input, &.{ 9, 0, 0, 0, 0, 0, 0, 0 });
}

fn linkOriginal(original: ir.Program) !data.linker.Linked {
    const borrows = try a.alloc(data.borrow_contract.Summary, original.functions.len);
    defer a.free(borrows);
    for (borrows, 0..) |*summary, id| summary.* = .{ .function = id };
    const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = original.roots.entry } }}, .borrows = borrows };
    const bytes = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(bytes);
    _ = try data.component.encode(a, object, bytes);
    var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "context", .object = bytes }}, &.{}, .{ .instance = "context", .symbol = "main" }, .{ .contract = .semantic });
    errdefer linked.deinit();
    @memset(bytes, 0xff);
    return linked;
}
test "Boolean context tables preserve all small chains and noncommuting source-free order" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try booleanChain(arena.allocator());
    var checked = try data.context_compression.run(a, original, null, .{});
    defer checked.deinit();
    var statistics: data.closed_compilation.Statistics = .{};
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic, .statistics = &statistics });
    defer shared.deinit();
    std.debug.print("Boolean selection: {any}\n", .{statistics});
    var linked = try linkOriginal(original);
    defer linked.deinit();
    var cases: usize = 0;
    for (0..4) |length| {
        const count = @as(usize, 1) << @intCast(length * 2);
        for (0..count) |tables| for (0..2) |seed| {
            var input: [8]u8 = undefined;
            input[0] = @intCast(length);
            for (0..length) |i| {
                const table = (tables >> @intCast(2 * i)) & 3;
                input[1 + 2 * i] = @intCast(table & 1);
                input[2 + 2 * i] = @intCast((table >> 1) & 1);
            }
            input[1 + 2 * length] = @intCast(seed);
            // Independent oracle applies stored actions from inner to outer.
            var expected: u8 = @intCast(seed);
            var index = length;
            while (index != 0) {
                index -= 1;
                expected = input[1 + 2 * index + expected];
            }
            for ([_]ir.Program{ original, checked.program, shared.program, linked.program }, 0..) |program, arm| {
                const observed = try run(program, input[0 .. 2 + 2 * length], &.{expected});
                if (arm > 0) try std.testing.expect(observed.continuations <= 1);
            }
            cases += 1;
        };
    }
    std.debug.print("Boolean actions: {d} chains; {any}\n", .{ cases, statistics });
    var candidate = (try data.context_compression.construct(a, original, .{})).?;
    defer candidate.deinit();
    const blocks = try arena.allocator().dupe(ir.Block, candidate.program.blocks);
    const ops = try arena.allocator().dupe(ir.Instruction, blocks[4].instructions);
    ops[5] = .{ .destination = 6, .opcode = .select, .operands = &.{ 6, 9, 8 } };
    ops[6] = .{ .destination = 7, .opcode = .select, .operands = &.{ 7, 9, 8 } };
    const transfers = try arena.allocator().dupe(ir.Assignment, blocks[4].terminator.jump.assignments);
    transfers[1].source = .{ .slot = 6 };
    transfers[2].source = .{ .slot = 7 };
    blocks[4].terminator.jump.assignments = transfers;
    blocks[4].instructions = ops;
    var forged = candidate.program;
    forged.blocks = blocks;
    var admitted = try data.activation_ownership.analyze(a, forged);
    admitted.deinit();
    try std.testing.expectError(error.InvalidContextCompression, data.context_compression.validate(a, original, forged, candidate.sites, .{}));
    const input = [_]u8{ 2, 1, 0, 0, 0, 0 }; // outer NOT, inner constant false
    _ = try run(original, &input, &.{1});
    _ = try run(forged, &input, &.{0});
}
test "noncommutative summary retains bounded context through 4096 runtime actions" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try booleanChain(arena.allocator());
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer shared.deinit();
    var linked = try linkOriginal(original);
    defer linked.deinit();
    for ([_]usize{ 1, 16, 256, 4096 }) |n| {
        const input = try arena.allocator().alloc(u8, 2 * n + 11);
        var writer: data.wire.Writer = .{ .output = input };
        try writer.natural(n);
        const start = writer.position;
        for (0..n) |i| {
            const table: u8 = @intCast((i * 17 + i / 3) % 4);
            input[start + i * 2] = table & 1;
            input[start + i * 2 + 1] = (table >> 1) & 1;
        }
        input[start + 2 * n] = 1;
        var expected: u8 = 1;
        var index = n;
        while (index != 0) {
            index -= 1;
            expected = input[start + 2 * index + expected];
        }
        const before = try run(original, input[0 .. start + 2 * n + 1], &.{expected});
        const after = try run(shared.program, input[0 .. start + 2 * n + 1], &.{expected});
        const closed = try run(linked.program, input[0 .. start + 2 * n + 1], &.{expected});
        try std.testing.expectEqual(n, before.continuations);
        try std.testing.expect(after.continuations <= 1 and closed.continuations <= 1);
        try std.testing.expect(after.activation_bindings <= 4);
        std.debug.print("Boolean n={d} baseline={any} shared={any}\n", .{ n, before, after });
    }
}
test "checked addition keeps the original successful order where reassociation would overflow" {
    var original = xor_chain;
    var schemas = xor_chain.schemas[0..5].*;
    schemas[0] = .i8;
    original.schemas = &schemas;
    var blocks = xor_chain.blocks[0..6].*;
    blocks[5].instructions = &.{.{ .destination = 7, .opcode = .integer_add, .operands = &.{ 4, 6 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 0 }} }};
    original.blocks = &blocks;
    var stats: data.context_compression.Statistics = .{};
    var checked = try data.context_compression.run(a, original, &stats, .{});
    defer checked.deinit();
    try std.testing.expectEqual(@as(usize, 0), stats.contexts_compressed);
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer shared.deinit();
    for ([_]ir.Program{ original, checked.program, shared.program }) |program| _ = try run(program, &.{ 3, 127, 1, 255, 0 }, &.{127});
}
test "resource custody and individually reentered continuations retain their original images" {
    inline for (.{ boundary.source.examples.borrowOperands, boundary.source.examples.reentrant }) |example| {
        var b = boundary.source.Builder.init(a);
        defer b.deinit();
        var original = try boundary.program.compile(a, try example(&b));
        defer original.deinit();
        var stats: data.context_compression.Statistics = .{};
        var result = try data.context_compression.run(a, original.program, &stats, .{});
        defer result.deinit();
        try std.testing.expectEqual(@as(usize, 0), stats.contexts_compressed);
        try std.testing.expect(!stats.work_limit);
        try std.testing.expectEqual(try data.program_image.identity(a, original.program), try data.program_image.identity(a, result.program));
    }
}
