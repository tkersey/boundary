const std = @import("std");
const p = @import("program.zig");
const image = @import("image.zig");
const admission = @import("admission.zig");

pub const example: p.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 0 },
    .schemas = &.{.u64},
    .constants = &.{.{ .schema = 0, .bytes = &.{ 42, 0, 0, 0, 0, 0, 0, 0 } }},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .parameters = &.{}, .result = 0 }},
    .blocks = &.{.{
        .function = 0,
        .parameters = &.{},
        .instructions = &.{.{ .opcode = .constant, .result_type = 0 }},
        .terminator = .{ .return_value = 0 },
    }},
};

fn borrowFlowExample() p.Program {
    return .{
        .roots = .{ .entry = 2, .result = 0, .failure = 0 },
        .schemas = &.{ .unit, .{ .internal = .{ .region = 0 } } },
        .constants = &.{},
        .effects = &.{},
        .functions = &.{
            .{ .entry = 0, .parameters = &.{1}, .result = 1, .regions = &.{0} },
            .{ .entry = 1, .parameters = &.{1}, .result = 1, .regions = &.{0} },
            .{ .entry = 2, .parameters = &.{0}, .result = 0 },
        },
        .blocks = &.{
            .{
                .function = 0,
                .parameters = &.{1},
                .instructions = &.{},
                .terminator = .{ .return_value = 0 },
            },
            .{
                .function = 1,
                .parameters = &.{1},
                .instructions = &.{},
                .terminator = .{ .return_value = 0 },
            },
            .{
                .function = 2,
                .parameters = &.{0},
                .instructions = &.{},
                .terminator = .{ .return_value = 0 },
            },
        },
        .scopes = .{ .region_count = 1 },
    };
}

test "settled borrow queries reuse results without allocating again" {
    const borrows = @import("borrow_flow.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = borrowFlowExample();
    try admission.program(arena.allocator(), program);
    var failing = std.testing.FailingAllocator.init(arena.allocator(), .{});
    const allocator = failing.allocator();
    const facts = try admission.schemas(allocator, program.schemas);
    var flow = try borrows.Flow.init(allocator, program, facts.exportable);
    const expected = [_]borrows.Source{.{ .parameter = 0 }};
    try std.testing.expectEqualSlices(borrows.Source, &expected, try flow.returned(0));
    failing.fail_index = failing.alloc_index;
    try std.testing.expectEqualSlices(borrows.Source, &expected, try flow.returned(0));
    try std.testing.expect(!failing.has_induced_failure);
}

test "a failed borrow query settles fully when the same query is retried" {
    const borrows = @import("borrow_flow.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = borrowFlowExample();
    try admission.program(arena.allocator(), program);
    var failing = std.testing.FailingAllocator.init(arena.allocator(), .{});
    const allocator = failing.allocator();
    const facts = try admission.schemas(allocator, program.schemas);
    var flow = try borrows.Flow.init(allocator, program, facts.exportable);
    _ = try flow.returned(0);
    // Reserve the new query so the injected failure occurs inside settlement.
    try flow.queries.ensureUnusedCapacity(allocator, 1);
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, flow.returned(1));
    try std.testing.expect(failing.has_induced_failure);
    failing.fail_index = std.math.maxInt(usize);
    const expected = [_]borrows.Source{.{ .parameter = 0 }};
    try std.testing.expectEqualSlices(borrows.Source, &expected, try flow.returned(1));
}

test "borrow validation batches independent function requirements" {
    const borrows = @import("borrow_flow.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var costs: [2]usize = undefined;
    for ([_]usize{ 8, 64 }, 0..) |count, sample| {
        var program = borrowFlowExample();
        var functions: [65]p.Function = undefined;
        var blocks: [65]p.Block = undefined;
        for (0..count) |index| {
            functions[index] = program.functions[0];
            functions[index].entry = index;
            blocks[index] = program.blocks[0];
            blocks[index].function = index;
        }
        functions[count] = program.functions[2];
        functions[count].entry = count;
        blocks[count] = program.blocks[2];
        blocks[count].function = count;
        program.roots.entry = count;
        program.functions = functions[0 .. count + 1];
        program.blocks = blocks[0 .. count + 1];
        try admission.program(arena.allocator(), program);
        const facts = try admission.schemas(arena.allocator(), program.schemas);
        var counted = std.testing.FailingAllocator.init(arena.allocator(), .{});
        try borrows.validate(counted.allocator(), program, facts.exportable, null);
        costs[sample] = counted.allocations;
    }
    // Eight times as many independent functions must not cause quadratic
    // repetitions of the already completed analyses.
    try std.testing.expect(costs[1] <= costs[0] * 16);
}

test "internal operation resumption values remain first-order" {
    var program = example;
    program.schemas = &.{ .u64, .{ .internal = .{ .capability = 0 } } };
    program.effects = &.{.{ .identity = "internal-result", .payload = 0, .result = 1, .external = false }};
    try std.testing.expectError(error.InvalidEffect, admission.program(std.testing.allocator, program));
    program.effects = &.{.{ .identity = "internal-result", .payload = 1, .result = 0, .external = false }};
    try admission.program(std.testing.allocator, program);
}

test "BPI2 roundtrip owns decoded data and leaves the source independent" {
    var buffer: [1024]u8 = undefined;
    const bytes = try image.encode(std.testing.allocator, example, &buffer);
    var decoded = try image.decode(std.testing.allocator, bytes);
    defer decoded.deinit();
    @memset(&buffer, 0xa5);
    try std.testing.expectEqual(@as(u8, 42), decoded.program.constants[0].bytes[0]);
    var again: [1024]u8 = undefined;
    const encoded = try image.encode(std.testing.allocator, decoded.program, &again);
    try std.testing.expectEqualSlices(u8, decoded.bytes, encoded);
}

test "canonical catalogs remove unused declarations and ignore allocation ordinals" {
    const canonical = @import("canonical.zig");
    const reordered: p.Program = .{
        .roots = .{ .entry = 1, .result = 1, .failure = 1 },
        .schemas = &.{ .boolean, .u64, .{ .internal = .{ .computation = .{ .parameters = &.{}, .result = 0 } } } },
        .constants = &.{
            .{ .schema = 0, .bytes = &.{1} },
            .{ .schema = 1, .bytes = &.{ 42, 0, 0, 0, 0, 0, 0, 0 } },
            .{ .schema = 1, .bytes = &.{ 99, 0, 0, 0, 0, 0, 0, 0 } },
        },
        .effects = &.{.{ .identity = "unused", .payload = 0, .result = 0 }},
        .functions = &.{
            .{ .entry = 0, .parameters = &.{}, .result = 0 },
            .{ .entry = 1, .parameters = &.{}, .result = 1 },
        },
        .blocks = &.{
            .{ .function = 0, .parameters = &.{}, .instructions = &.{.{ .opcode = .constant, .result_type = 0 }}, .terminator = .{ .return_value = 0 } },
            .{ .function = 1, .parameters = &.{}, .instructions = &.{.{ .opcode = .constant, .result_type = 1, .immediate = 1 }}, .terminator = .{ .return_value = 0 } },
        },
        .scopes = .{ .region_count = 7, .captures = &.{.{ .fields = &.{}, .use = .reusable }} },
        .constructors = &.{.{ .function = 0, .capture = 0, .schema = 2 }},
    };
    try admission.program(std.testing.allocator, reordered);
    var normalized = try canonical.normalize(std.testing.allocator, reordered);
    defer normalized.deinit();
    try std.testing.expect(canonical.equal(p.Program, example, normalized.program));
    try canonical.require(std.testing.allocator, normalized.program);
    var output: [1024]u8 = @splat(0xcc);
    try std.testing.expectError(error.NonCanonical, image.encode(std.testing.allocator, reordered, &output));
    try std.testing.expectEqualSlices(u8, &@as([1024]u8, @splat(0xcc)), &output);
    const Attempts = struct {
        fn run(allocator: std.mem.Allocator, input: p.Program) !void {
            var value = try canonical.normalize(allocator, input);
            defer value.deinit();
            try std.testing.expect(canonical.equal(p.Program, example, value.program));
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Attempts.run, .{reordered});
}

test "reachable equal constants share one owned payload after normalization" {
    const canonical = @import("canonical.zig");
    var payload = [_]u8{ 42, 0, 0, 0, 0, 0, 0, 0 };
    var input = example;
    input.constants = &.{ .{ .schema = 0, .bytes = &payload }, .{ .schema = 0, .bytes = &payload } };
    input.blocks = &.{.{
        .function = 0,
        .parameters = &.{},
        .instructions = &.{ .{ .opcode = .constant, .result_type = 0 }, .{ .opcode = .constant, .result_type = 0, .immediate = 1 } },
        .terminator = .{ .return_value = 1 },
    }};
    var normalized = try canonical.normalize(std.testing.allocator, input);
    defer normalized.deinit();
    @memset(&payload, 0);
    try std.testing.expectEqual(@as(usize, 1), normalized.program.constants.len);
    try std.testing.expectEqual(@as(u8, 42), normalized.program.constants[0].bytes[0]);
    for (normalized.program.blocks[0].instructions) |instruction| try std.testing.expectEqual(@as(p.Id, 0), instruction.immediate);
    try canonical.require(std.testing.allocator, normalized.program);
}

test "forged register and type declarations reject through public admission" {
    var bad = example;
    var blocks = [_]p.Block{example.blocks[0]};
    blocks[0].terminator = .{ .return_value = 1 };
    bad.blocks = &blocks;
    try std.testing.expectError(error.InvalidReference, admission.program(std.testing.allocator, bad));
    bad = example;
    bad.constants = &.{.{ .schema = 0, .bytes = &.{1} }};
    try std.testing.expectError(error.InvalidValue, admission.program(std.testing.allocator, bad));
}

test "productive recursive schemas and zero-width sequences have finite validation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const catalog: []const p.Schema = &.{ .unit, .{ .sum = &.{ 0, 2 } }, .{ .product = &.{ 0, 1 } }, .{ .seq = 0 } };
    const facts = try admission.schemas(arena.allocator(), catalog);
    try admission.value(arena.allocator(), catalog, facts, .{ .schema = 1, .bytes = &.{ 1, 1, 0 } });
    try admission.value(arena.allocator(), catalog, facts, .{ .schema = 3, .bytes = &.{ 255, 255, 255, 255, 255, 255, 255, 255, 255, 1 } });
    try std.testing.expectError(error.InvalidSchema, admission.schemas(arena.allocator(), &.{.{ .product = &.{0} }}));
}

test "fixed arrays and bounded byte domains retain their exact external contracts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const types: []const p.Schema = &.{
        .u8,                    .{ .array = .{ .element = 0, .length = 2 } }, .{ .bounded_bytes = 2 },
        .{ .bounded_text = 2 }, .unit,                                        .{ .array = .{ .element = 4, .length = std.math.maxInt(u64) } },
    };
    const facts = try admission.schemas(allocator, types);
    try admission.value(allocator, types, facts, .{ .schema = 1, .bytes = &.{ 4, 5 } });
    try std.testing.expectError(error.InvalidValue, admission.value(allocator, types, facts, .{ .schema = 1, .bytes = &.{4} }));
    try std.testing.expectError(error.NonCanonical, admission.value(allocator, types, facts, .{ .schema = 1, .bytes = &.{ 4, 5, 6 } }));
    try admission.value(allocator, types, facts, .{ .schema = 2, .bytes = &.{ 2, 0xff, 0 } });
    try admission.value(allocator, types, facts, .{ .schema = 3, .bytes = &.{ 2, 0xc3, 0xa9 } });
    try std.testing.expectError(error.InvalidValue, admission.value(allocator, types, facts, .{ .schema = 2, .bytes = &.{ 3, 1, 2, 3 } }));
    try std.testing.expectError(error.InvalidUtf8, admission.value(allocator, types, facts, .{ .schema = 3, .bytes = &.{ 1, 0xff } }));
    try admission.value(allocator, types, facts, .{ .schema = 5, .bytes = &.{} });
}

test "finite and empty enumerations reject every undeclared value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const types: []const p.Schema = &.{ .{ .enumeration = &.{ 2, 7 } }, .{ .enumeration = &.{} } };
    const facts = try admission.schemas(allocator, types);
    try admission.value(allocator, types, facts, .{ .schema = 0, .bytes = &.{ 7, 0, 0, 0 } });
    try std.testing.expectError(error.InvalidValue, admission.value(allocator, types, facts, .{ .schema = 0, .bytes = &.{ 5, 0, 0, 0 } }));
    try std.testing.expectError(error.InvalidValue, admission.value(allocator, types, facts, .{ .schema = 1, .bytes = &.{ 0, 0, 0, 0 } }));
    try std.testing.expectError(error.InvalidSchema, admission.schemas(allocator, &.{.{ .enumeration = &.{ 7, 2 } }}));
    try std.testing.expectError(error.InvalidSchema, admission.schemas(allocator, &.{.{ .enumeration = &.{ 2, 2 } }}));
}
