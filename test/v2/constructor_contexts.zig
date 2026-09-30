// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const data = @import("boundary_data");
const boundary = @import("boundary");
const world = @import("world");
const ir = data.activation;
const p = data.program;
const a = std.testing.allocator;
/// Pure recursive map: each returned constructor prepends a negated head.
pub const mapped: ir.Program = .{
    .roots = .{ .entry = 0, .result = 5, .failure = 1 },
    .schemas = &.{ .boolean, .unit, .{ .vector = .{ .element = 0, .maximum = 4096 } }, .{ .product = &.{ 0, 2 } }, .{ .sum = &.{ 1, 3 } }, .{ .vector = .{ .element = 0, .maximum = 4096 } } },
    .constants = &.{.{ .schema = 1, .bytes = &.{} }},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 2, 5 } }, .result = 5 },
        .{ .entry = 2, .inputs = &.{0}, .layout = .{ .slots = &.{ 2, 4, 3, 0, 2, 0, 5, 5, 5 } }, .result = 5 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{0}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 1, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 1, .opcode = .sequence_pop, .operands = &.{0} }}, .terminator = .{ .switch_variant = .{ .value = 1, .cases = &.{ .{ .block = 3 }, .{ .block = 4 } } } } },
        .{ .function = 1, .instructions = &.{.{ .destination = 6, .opcode = .sequence }}, .terminator = .{ .return_value = 6 } },
        .{ .function = 1, .instructions = &.{
            .{ .destination = 2, .opcode = .variant_payload, .operands = &.{1}, .immediate = 1, .failures = &.{.{ .kind = .invalid_variant, .value = 0 }} },
            .{ .destination = 3, .opcode = .field, .operands = &.{2}, .immediate = 0 },
            .{ .destination = 4, .opcode = .field, .operands = &.{2}, .immediate = 1 },
            .{ .destination = 5, .opcode = .boolean_not, .operands = &.{3} },
        }, .terminator = .{ .call = .{ .function = 1, .arguments = &.{4}, .next = .{ .block = 5, .assignments = &.{.{ .destination = 6, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{
            .{ .destination = 7, .opcode = .sequence, .operands = &.{5} },
            .{ .destination = 8, .opcode = .sequence_concat, .operands = &.{ 7, 6 }, .failures = &.{.{ .kind = .capacity_exceeded, .value = 0 }} },
        }, .terminator = .{ .return_value = 8 } },
    },
};
pub fn paired(allocator: std.mem.Allocator) !ir.Program {
    var result = mapped;
    const schemas = try allocator.dupe(p.Schema, mapped.schemas);
    schemas[5].vector.maximum = 8192;
    result.schemas = schemas;
    const blocks = try allocator.dupe(ir.Block, mapped.blocks);
    const instructions = try allocator.dupe(ir.Instruction, blocks[5].instructions);
    instructions[0].operands = &.{ 3, 5 };
    blocks[5].instructions = instructions;
    result.blocks = blocks;
    return result;
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
const Traffic = struct { allocations: usize, allocated_bytes: usize };
fn traffic(program: ir.Program, input: []const u8, expected: []const u8) !Traffic {
    const bytes = try image(program);
    defer a.free(bytes);
    var counter = std.testing.FailingAllocator.init(a, .{});
    {
        var session = try world.Session.initImage(counter.allocator(), bytes, input);
        defer session.deinit();
        const out = try session.run(null);
        try std.testing.expect(out == .completed);
        try std.testing.expectEqualSlices(u8, expected, try session.bytes(&out.completed));
    }
    try std.testing.expectEqual(counter.allocated_bytes, counter.freed_bytes);
    return .{ .allocations = counter.allocations, .allocated_bytes = counter.allocated_bytes };
}
test "persistent constructor workers preserve ordered outputs with bounded pending frames" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    for ([_]ir.Program{ mapped, try paired(arena.allocator()) }, 1..) |original, width| {
        var checked = try data.constructor_contexts.run(a, original, null, .{});
        defer checked.deinit();
        var stats: data.closed_compilation.Statistics = .{};
        var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic, .statistics = &stats });
        defer shared.deinit();
        var linked = try linkOriginal(original);
        defer linked.deinit();
        std.debug.print("constructor width={d} {any}\n", .{ width, stats });
        for ([_]usize{ 0, 1, 16, 256, 4096 }) |n| {
            const input = try arena.allocator().alloc(u8, n + 10);
            var iw: data.wire.Writer = .{ .output = input };
            try iw.natural(n);
            const expected = try arena.allocator().alloc(u8, n * width + 10);
            var ew: data.wire.Writer = .{ .output = expected };
            try ew.natural(n * width);
            for (0..n) |i| {
                const value: u8 = @intCast((i + i / 3) % 2);
                input[iw.position] = value;
                iw.position += 1;
                if (width == 2) {
                    expected[ew.position] = value;
                    ew.position += 1;
                }
                expected[ew.position] = 1 - value;
                ew.position += 1;
            }
            const before = try run(original, input[0..iw.position], expected[0..ew.position]);
            const after = try run(checked.program, input[0..iw.position], expected[0..ew.position]);
            const integrated = try run(shared.program, input[0..iw.position], expected[0..ew.position]);
            const source_free = try run(linked.program, input[0..iw.position], expected[0..ew.position]);
            try std.testing.expectEqual(@as(usize, 0), source_free.continuations);
            try std.testing.expectEqual(n, before.continuations);
            try std.testing.expectEqual(@as(usize, 0), after.continuations);
            try std.testing.expectEqual(@as(usize, 0), integrated.continuations);
            const before_traffic = try traffic(original, input[0..iw.position], expected[0..ew.position]);
            const after_traffic = try traffic(shared.program, input[0..iw.position], expected[0..ew.position]);
            std.debug.print("traffic width={d} n={d}: before={any} after={any}\n", .{ width, n, before_traffic, after_traffic });
            std.debug.print("width={d} n={d} output={d} before={any} after={any} shared={any}\n", .{ width, n, ew.position, before, after, integrated });
        }
    }
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

test "an existing caller alias retains the input sequence while the worker constructs its output" {
    var original = mapped;
    original.schemas = &.{ mapped.schemas[0], mapped.schemas[1], mapped.schemas[2], mapped.schemas[3], mapped.schemas[4], mapped.schemas[5], .{ .product = &.{ 2, 5 } } };
    original.roots.result = 6;
    var functions = mapped.functions[0..2].*;
    functions[0].layout.slots = &.{ 2, 5, 6 };
    functions[0].result = 6;
    original.functions = &functions;
    var blocks = mapped.blocks[0..6].*;
    blocks[1].instructions = &.{.{ .destination = 2, .opcode = .product, .operands = &.{ 0, 1 } }};
    blocks[1].terminator = .{ .return_value = 2 };
    original.blocks = &blocks;
    var shared = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer shared.deinit();
    var linked = try linkOriginal(original);
    defer linked.deinit();
    for ([_]ir.Program{ original, shared.program, linked.program }, 0..) |program, arm| {
        const result = try run(program, &.{ 4, 1, 0, 0, 1 }, &.{ 4, 1, 0, 0, 1, 4, 0, 1, 1, 0 });
        if (arm > 0) try std.testing.expect(result.continuations <= 1);
    }
}
test "reversed constructor composition is admitted but returns an observably different order" {
    var candidate = (try data.constructor_contexts.construct(a, mapped, .{})).?;
    defer candidate.deinit();
    const blocks = try a.dupe(ir.Block, candidate.program.blocks);
    defer a.free(blocks);
    const instructions = try a.dupe(ir.Instruction, blocks[4].instructions);
    defer a.free(instructions);
    instructions[instructions.len - 1].operands = &.{ 7, 6 };
    blocks[4].instructions = instructions;
    var forged = candidate.program;
    forged.blocks = blocks;
    var admitted = try data.activation_ownership.analyze(a, forged);
    admitted.deinit();
    try std.testing.expectError(error.InvalidConstructorContext, data.constructor_contexts.validate(a, mapped, forged, candidate.sites, .{}));
    _ = try run(mapped, &.{ 3, 1, 1, 0 }, &.{ 3, 0, 0, 1 });
    _ = try run(forged, &.{ 3, 1, 1, 0 }, &.{ 3, 1, 0, 0 });
}
test "resource custody and individually reentered continuations retain their original images" {
    inline for (.{ boundary.source.examples.borrowOperands, boundary.source.examples.reentrant }) |example| {
        var b = boundary.source.Builder.init(a);
        defer b.deinit();
        var original = try boundary.program.compile(a, try example(&b));
        defer original.deinit();
        var stats: data.constructor_contexts.Statistics = .{};
        var result = try data.constructor_contexts.run(a, original.program, &stats, .{});
        defer result.deinit();
        try std.testing.expectEqual(@as(usize, 0), stats.contexts_lowered);
        try std.testing.expect(!stats.work_limit);
        try std.testing.expectEqual(try data.program_image.identity(a, original.program), try data.program_image.identity(a, result.program));
    }
}

fn execute(program: data.activation.Program, input: []const u8, expected: []const u8, expected_yields: usize) !usize {
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
    defer a.free(bytes);
    _ = try data.program_image.encode(a, program, bytes);
    var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = input }, .quantum = 1 });
    defer result.deinit();
    var steps: usize = 1;
    var yields: usize = 0;
    while (result.record == .progressed or result.record == .yielded) {
        try std.testing.expect(steps < 4096);
        const yielded = result.record == .yielded;
        yields += @intFromBool(yielded);
        const state = if (yielded) result.record.yielded.? else result.record.progressed.?;
        const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = state }, .control = if (yielded) .resume_yield else .none, .quantum = 1 });
        result.deinit();
        result = next;
        steps += 1;
    }
    try std.testing.expectEqual(expected_yields, yields);
    try std.testing.expect(result.record == .completed);
    try std.testing.expectEqualSlices(u8, expected, result.record.completed);
    return steps;
}
test "every intermediate constructor state restores as an initialized ordinary value" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const original = try paired(arena.allocator());
    var checked = try data.constructor_contexts.run(a, original, null, .{});
    defer checked.deinit();
    var linked = try linkOriginal(original);
    defer linked.deinit();
    for ([_]ir.Program{ original, checked.program, linked.program }) |program| _ = try execute(program, &.{ 4, 1, 0, 0, 1 }, &.{ 8, 1, 0, 0, 1, 0, 1, 1, 0 }, 0);
}
test "nonlinear reentry and cloned continuations keep their suspension and independent states" {
    inline for (.{ boundary.source.examples.reentrant, boundary.source.examples.cloned }) |example| {
        var builder = boundary.source.Builder.init(a);
        defer builder.deinit();
        var original = try boundary.program.compile(a, try example(&builder));
        defer original.deinit();
        var stats: data.constructor_contexts.Statistics = .{};
        var checked = try data.constructor_contexts.run(a, original.program, &stats, .{});
        defer checked.deinit();
        var shared = try data.closed_compilation.run(a, original.program, .{ .contract = .semantic });
        defer shared.deinit();
        try std.testing.expectEqual(@as(usize, 0), stats.contexts_lowered);
        for ([_]ir.Program{ original.program, checked.program, shared.program }) |program| _ = try execute(program, &.{}, &.{ 113, 0, 0, 0, 0, 0, 0, 0 }, 1);
    }
}
