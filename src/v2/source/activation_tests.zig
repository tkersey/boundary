// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const source = @import("../source.zig");
const lower = @import("activation_lower.zig").lower;
const data = @import("boundary_data_v2");
const ir = data.activation;
const p = data.program;
const testing = std.testing;
const check = @import("check.zig");

test "installation lowering establishes each result once without pass-through interfaces" {
    for ([_]usize{ 1, 8, 64, 128, 256 }) |count| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        const input = try source.examples.installations(&builder, count);
        var compiled = try lower(testing.allocator, input);
        defer compiled.deinit();
        const image = compiled.program;
        try data.activation_structure.validate(testing.allocator, image);
        const flow = compiled.flow;
        try testing.expect(flow.block_visits <= image.blocks.len * 2);
        try testing.expect(flow.liveness_visits <= image.blocks.len * 4);
        const entry = image.functions[@intCast(image.roots.entry)];
        try testing.expectEqual(4 * count + 1, entry.layout.slots.len);
        try testing.expectEqual(0, entry.inputs.len);
        var blocks: usize = 0;
        var instructions: usize = 0;
        var results: usize = 0;
        var sums: usize = 0;
        for (image.blocks) |block| {
            if (block.function != image.roots.entry) continue;
            blocks += 1;
            instructions += block.instructions.len;
            switch (block.terminator) {
                .handle => |handle| {
                    try testing.expectEqual(1, handle.next.assignments.len);
                    try testing.expect(handle.next.assignments[0].source == .returned);
                    results += 1;
                },
                .jump => |edge| try testing.expectEqual(0, edge.assignments.len),
                .return_value => {
                    for (block.instructions) |operation| {
                        if (operation.opcode == .integer_add) sums += 1;
                    }
                },
                else => return error.TestUnexpectedResult,
            }
        }
        try testing.expectEqual(2 * count + 1, blocks);
        try testing.expectEqual(3 * count + 1, instructions);
        try testing.expectEqual(count, results);
        // The checked sum still occurs after all the handler installations.
        try testing.expectEqual(count, sums);
    }
}

test "stable source analysis shares growing free-variable sets" {
    for ([_]usize{ 1, 8, 64, 128, 256, 512, 1024 }) |count| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        const input = try source.examples.installations(&builder, count);
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const facts = try check.analyze(arena.allocator(), input);
        // Counts cover the actual pool, including intermediate fixed-point work.
        // Logical memberships grow quadratically; stored descriptions must not.
        try testing.expect(facts.sets.nodes.items.len <= 4 * count + 64);
        try testing.expect(facts.sets.visits <= 24 * count + 128);
        try testing.expectEqual(0, facts.functions[@intCast(input.entry)].items.len);
    }
}

test "stable source analysis closes mutually recursive lexical captures" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const boolean = try builder.scalar(bool);
    const unit = try builder.scalar(void);
    const main = try builder.declare(&.{integer}, integer, &.{}, &.{});
    const left = try builder.declare(&.{integer}, integer, &.{}, &.{});
    const right = try builder.declare(&.{integer}, integer, &.{}, &.{});
    const outer = builder.parameter(main, 0);
    const failure = try builder.failureLiteral(try builder.constant(void, {}));
    for ([_]p.Id{ left, right }, [_]p.Id{ right, left }) |function, other| {
        const n = try builder.reference(builder.parameter(function, 0));
        const condition = try builder.primitive(boolean, .equal, &.{ n, try builder.constant(u64, 0) }, 0);
        const decrement = try builder.value(.{ .schema = integer, .expression = .{ .primitive = .{
            .opcode = .integer_sub,
            .operands = &.{ n, try builder.constant(u64, 1) },
            .failures = &.{.{ .kind = .arithmetic_overflow, .value = failure }},
        } } });
        const call = try builder.term(.{ .call = .{ .function = other, .arguments = &.{decrement} } });
        try builder.define(function, try builder.term(.{ .conditional = .{
            .condition = condition,
            .when_true = try builder.pure(try builder.reference(outer)),
            .when_false = call,
        } }));
    }
    try builder.define(main, try builder.term(.{ .call = .{
        .function = left,
        .arguments = &.{try builder.constant(u64, 3)},
    } }));
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const facts = try check.analyze(arena.allocator(), builder.module(main, unit));
    try testing.expectEqualSlices(p.Id, &.{outer}, facts.functions[@intCast(left)].items);
    try testing.expectEqualSlices(p.Id, &.{outer}, facts.functions[@intCast(right)].items);
    try testing.expectEqual(0, facts.functions[@intCast(main)].items.len);
}

test "both conditional arms write the same stable join slot" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const boolean = try builder.scalar(bool);
    const unit = try builder.scalar(void);
    const main = try builder.declare(&.{boolean}, integer, &.{}, &.{});
    const binding = try builder.variable(integer);
    const left = try builder.pure(try builder.constant(u64, 17));
    const right = try builder.pure(try builder.constant(u64, 31));
    const branch = try builder.term(.{ .conditional = .{
        .condition = try builder.reference(builder.parameter(main, 0)),
        .when_true = left,
        .when_false = right,
    } });
    try builder.define(main, try builder.bind(binding, branch, try builder.pure(try builder.reference(binding))));
    var compiled = try lower(testing.allocator, builder.module(main, unit));
    defer compiled.deinit();
    const image = compiled.program;
    try data.activation_structure.validate(testing.allocator, image);

    const root = image.blocks[@intCast(image.functions[@intCast(main)].entry)];
    const conditional = image.blocks[@intCast(root.terminator.jump.block)].terminator.branch;
    const a = image.blocks[@intCast(conditional.when_true.block)];
    const b = image.blocks[@intCast(conditional.when_false.block)];
    try testing.expectEqual(a.terminator.jump.block, b.terminator.jump.block);
    try testing.expectEqual(a.terminator.jump.assignments[0].destination, b.terminator.jump.assignments[0].destination);
    const joined = image.blocks[@intCast(a.terminator.jump.block)];
    try testing.expectEqual(joined.terminator.return_value, a.terminator.jump.assignments[0].destination);
    try testing.expect(a.terminator.jump.assignments[0].source.slot !=
        b.terminator.jump.assignments[0].source.slot);
}

test "reused lexical name has distinct stable bindings" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const unit = try builder.scalar(void);
    const main = try builder.declare(&.{}, integer, &.{}, &.{});
    const name = try builder.variable(integer);
    const value = try builder.reference(name);
    const inner = try builder.bind(name, try builder.pure(try builder.constant(u64, 2)), try builder.pure(value));
    try builder.define(main, try builder.bind(name, try builder.pure(try builder.constant(u64, 1)), inner));
    var compiled = try lower(testing.allocator, builder.module(main, unit));
    defer compiled.deinit();
    const image = compiled.program;
    try data.activation_structure.validate(testing.allocator, image);

    var destinations: [2]p.Id = undefined;
    var count: usize = 0;
    var result: ?p.Id = null;
    for (image.blocks) |block| switch (block.terminator) {
        .jump => |edge| for (edge.assignments) |assignment| {
            destinations[count] = assignment.destination;
            count += 1;
        },
        .return_value => |slot| result = slot,
        else => return error.TestUnexpectedResult,
    };
    try testing.expectEqual(2, count);
    try testing.expect(destinations[0] != destinations[1]);
    try testing.expectEqual(destinations[1], result.?);
}

fn ownedConstruction(allocator: std.mem.Allocator) !void {
    var builder = source.Builder.init(allocator);
    var alive = true;
    defer if (alive) builder.deinit();
    const input = try source.examples.installations(&builder, 2);
    var compiled = try lower(allocator, input);
    defer compiled.deinit();
    builder.deinit();
    alive = false;
    try testing.expectEqualStrings("economy/read", compiled.program.effects[0].identity);
    const entry = compiled.program.functions[@intCast(compiled.program.roots.entry)];
    try testing.expectEqual(9, entry.layout.slots.len);
}

test "construction owns source data and releases every partial allocation" {
    try testing.checkAllAllocationFailures(testing.allocator, ownedConstruction, .{});
}

test "stable lowering shares pure DAG expressions without enumerating their tree" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const unit = try builder.scalar(void);
    const failure = try builder.failureLiteral(try builder.constant(void, {}));
    var value = try builder.constant(u64, 1);
    for (0..32) |_| value = try builder.value(.{
        .schema = integer,
        .expression = .{ .primitive = .{
            .opcode = .integer_add,
            .operands = &.{ value, value },
            .failures = &.{.{ .kind = .arithmetic_overflow, .value = failure }},
        } },
    });
    const main = try builder.declare(&.{}, integer, &.{}, &.{});
    try builder.define(main, try builder.pure(value));
    var compiled = try lower(testing.allocator, builder.module(main, unit));
    defer compiled.deinit();
    try testing.expectEqual(1, compiled.program.blocks.len);
    try testing.expectEqual(33, compiled.program.blocks[0].instructions.len);
    try testing.expectEqual(33, compiled.program.functions[0].layout.slots.len);
}

test "stable lowering distinguishes the successor handler answer from the resumption answer" {
    var builder = source.Builder.init(testing.allocator);
    defer builder.deinit();
    var compiled = try lower(testing.allocator, try source.examples.successorState(&builder));
    defer compiled.deinit();
    var image = compiled.program;
    try data.activation_structure.validate(testing.allocator, image);

    const blocks = try testing.allocator.dupe(ir.Block, image.blocks);
    defer testing.allocator.free(blocks);
    image.blocks = blocks;
    for (blocks) |*block| {
        if (block.terminator != .resume_with) continue;
        const operation = block.terminator.resume_with;
        const layout = image.functions[@intCast(block.function)].layout.slots;
        const schema = layout[@intCast(operation.resumption)];
        const signature = image.schemas[@intCast(schema)].internal.resumption;
        const handler = image.handlers[@intCast(operation.handler)];
        if (signature.answer == handler.answer) continue;
        try testing.expectEqual(signature.answer, layout[@intCast(operation.argument)]);
        const assignments = [_]ir.Assignment{.{
            .destination = operation.argument,
            .source = .returned,
        }};
        block.terminator.resume_with.next.assignments = &assignments;
        try testing.expectError(error.TypeMismatch, data.activation_structure.validate(testing.allocator, image));
        return;
    }
    return error.TestUnexpectedResult;
}

test "generalized-effect staged examples lower directly without predecessor code" {
    // These checks establish construction, not runtime or target admission.
    inline for (.{
        "lexical",            "deep",                "recursive",      "choicesAll",         "choicesFirst",
        "generator",          "stateLocal",          "stateShared",    "ownership",          "answers",
        "scopedReader",       "writerRaise",         "schedulerFifo",  "yieldingCleanup",    "borrowOperands",
        "resourceScalar",     "resourcePair",        "boundedValues",  "queensDfs",          "queensBfs",
        "nested",             "shallow",             "injection",      "indexed",            "abortCustody",
        "unwind",             "reentrant",           "cloned",         "shallowResumptions", "shallowInjection",
        "handleOperandOrder", "protectOperandOrder", "successorState", "clausePayload",      "clauseAbort",
        "blobCapture",
    }) |name| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        var compiled = try lower(testing.allocator, try @field(source.examples, name)(&builder));
        defer compiled.deinit();
        try data.activation_structure.validate(testing.allocator, compiled.program);

        try testing.expect(compiled.program.blocks.len != 0);
    }
}
