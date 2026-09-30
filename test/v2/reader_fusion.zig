const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const a = std.testing.allocator;
pub const readers: ir.Program = .{
    .roots = .{ .entry = 0, .result = 2, .failure = 1 },
    .schemas = &.{
        .boolean,                                                                                                             .unit,                                                                                                                          .{ .product = &.{ 0, 0 } },                                                                                                                                           .{ .internal = .{ .capability = 0 } },                                                                                                                                                  .{ .internal = .{ .capability = 1 } },
        .{ .internal = .{ .computation = .{ .parameters = &.{3}, .result = 2, .effects = &.{0}, .capture_bound = &.{0} } } }, .{ .internal = .{ .computation = .{ .parameters = &.{4}, .result = 2, .effects = &.{ 0, 1 }, .capture_bound = &.{ 0, 3 } } } }, .{ .internal = .{ .resumption = .{ .effect = 0, .input = 0, .answer = 2, .handled = &.{0}, .capture_bound = &.{ 0, 1, 2, 3, 4 }, .mode = .deep, .use = .linear } } }, .{ .internal = .{ .resumption = .{ .effect = 1, .input = 0, .answer = 2, .effects = &.{0}, .handled = &.{1}, .capture_bound = &.{ 0, 1, 2, 3, 4 }, .mode = .deep, .use = .linear } } },
    },
    .constants = &.{.{ .schema = 1, .bytes = &.{} }},
    .effects = &.{ .{ .identity = "reader.left", .payload = 1, .result = 0, .external = false }, .{ .identity = "reader.right", .payload = 1, .result = 0, .external = false } },
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 5, 2 } }, .result = 2 },
        .{ .entry = 2, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 0, 0, 0, 3, 6, 2 } }, .result = 2, .effects = &.{0} },
        .{ .entry = 4, .inputs = &.{ 0, 1, 2, 3 }, .layout = .{ .slots = &.{ 3, 0, 0, 4, 1, 0, 0, 2 } }, .result = 2, .effects = &.{ 0, 1 } },
        .{ .entry = 11, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 2 } }, .result = 2 },
        .{ .entry = 12, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 1 } }, .result = 0 },
        .{ .entry = 13, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 1 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 4, .opcode = .computation, .operands = &.{ 1, 2, 3 }, .immediate = 0 }}, .terminator = .{ .handle = .{ .handler = 0, .body = 4, .arguments = &.{}, .state = &.{0}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 5 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 4, .opcode = .computation, .operands = &.{ 3, 1, 2 }, .immediate = 1 }}, .terminator = .{ .handle = .{ .handler = 1, .body = 4, .arguments = &.{}, .state = &.{0}, .next = .{ .block = 3, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 5 } },
        .{ .function = 2, .instructions = &.{.{ .destination = 4, .opcode = .constant }}, .terminator = .{ .branch = .{ .condition = 1, .when_true = .{ .block = 5 }, .when_false = .{ .block = 6 } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 4, .next = .{ .block = 7, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .perform = .{ .effect = 1, .capability = 3, .payload = 4, .next = .{ .block = 7, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 2, .when_true = .{ .block = 8 }, .when_false = .{ .block = 9 } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 4, .next = .{ .block = 10, .assignments = &.{.{ .destination = 6, .source = .returned }} } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .perform = .{ .effect = 1, .capability = 3, .payload = 4, .next = .{ .block = 10, .assignments = &.{.{ .destination = 6, .source = .returned }} } } } },
        .{ .function = 2, .instructions = &.{.{ .destination = 7, .opcode = .product, .operands = &.{ 5, 6 } }}, .terminator = .{ .return_value = 7 } },
        .{ .function = 3, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
        .{ .function = 4, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 5, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
    },
    .handlers = &.{
        .{ .mode = .deep, .input = 2, .answer = 2, .return_function = 3, .state = &.{0}, .clauses = &.{.{ .effect = 0, .function = 4, .resumption = 7, .strategy = .tail }} },
        .{ .mode = .deep, .input = 2, .answer = 2, .return_function = 3, .state = &.{0}, .effects = &.{0}, .clauses = &.{.{ .effect = 1, .function = 5, .resumption = 8, .strategy = .tail }} },
    },
    .constructors = &.{ .{ .function = 1, .capture = 0, .schema = 5 }, .{ .function = 2, .capture = 1, .schema = 6 } },
    .scopes = .{ .captures = &.{ .{ .fields = &.{ 0, 0, 0 }, .use = .reusable }, .{ .fields = &.{ 3, 0, 0 }, .use = .reusable } } },
};

/// Rename the two nominal Reader effects without changing nesting or positions.
pub fn reverseReaderEffects(allocator: std.mem.Allocator, original: ir.Program) !ir.Program {
    std.debug.assert(original.effects.len == 2);
    var maps = try data.relocation.identityMaps(allocator, try data.relocation.sizes(original));
    maps[@intFromEnum(data.relocation.Kind.effect)] = &.{ 1, 0 };
    const mapper: data.relocation.Mapper = .{ .allocator = allocator, .maps = maps };
    var result = original;
    const schemas = try allocator.alloc(data.program.Schema, original.schemas.len);
    for (original.schemas, schemas) |old, *new| new.* = try mapper.schema(old);
    const functions = try allocator.alloc(ir.Function, original.functions.len);
    for (original.functions, functions) |old, *new| new.* = try mapper.function(old);
    const blocks = try allocator.alloc(ir.Block, original.blocks.len);
    for (original.blocks, blocks) |old, *new| new.* = try mapper.block(old);
    const handlers = try allocator.alloc(ir.Handler, original.handlers.len);
    for (original.handlers, handlers) |old, *new| new.* = try mapper.handler(old);
    result.schemas = schemas;
    result.functions = functions;
    result.blocks = blocks;
    result.handlers = handlers;
    result.effects = try allocator.dupe(@TypeOf(original.effects[0]), &.{ original.effects[1], original.effects[0] });
    return result;
}

test "disjoint Reader fusion preserves every Boolean state and operation choice through closed linking" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    for ([_]ir.Program{ readers, try reverseReaderEffects(arena.allocator(), readers) }) |original| {
        var baseline = try data.closed_compilation.run(a, original, .{});
        defer baseline.deinit();
        var fused = try data.reader_fusion.run(a, original, null, .{});
        defer fused.deinit();
        var stats: data.closed_compilation.Statistics = .{};
        var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic, .statistics = &stats });
        defer compiled.deinit();
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 }, .{ .function = 3 }, .{ .function = 4 }, .{ .function = 5 } } };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "original", .object = encoded }}, &.{}, .{ .instance = "original", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        std.debug.print("original standalone={d} shared={d} linked={d}; {any}\n", .{ fused.program.handlers.len, compiled.program.handlers.len, linked.program.handlers.len, stats });
        try std.testing.expectEqual(@as(usize, 1), fused.program.handlers.len);
        try std.testing.expectEqual(@as(usize, 1), compiled.program.handlers.len);
        try std.testing.expectEqual(@as(usize, 1), linked.program.handlers.len);
        for (0..2) |left| for (0..2) |right| for (0..2) |first| for (0..2) |second| {
            const input = [_]u8{ @intCast(left), @intCast(right), @intCast(first), @intCast(second) };
            const expected = [_]u8{ @intCast(if (first == 1) left else right), @intCast(if (second == 1) left else right) };
            for ([_]ir.Program{ baseline.program, fused.program, compiled.program, linked.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &input }, .quantum = 1 });
                defer result.deinit();
                var steps: usize = 1;
                while (result.record == .progressed) {
                    try std.testing.expect(steps < 128);
                    const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = result.record.progressed.? }, .quantum = 1 });
                    result.deinit();
                    result = next;
                    steps += 1;
                }
                try std.testing.expect(result.record == .completed);
                try std.testing.expectEqualSlices(u8, &expected, result.record.completed);
            }
        };
    }
}

pub fn composedReturns(allocator: std.mem.Allocator) !ir.Program {
    var program = readers;
    const functions = try allocator.alloc(ir.Function, readers.functions.len + 1);
    @memcpy(functions[0..readers.functions.len], readers.functions);
    functions[3].layout.slots = &.{ 0, 2, 0, 0, 0, 2 };
    functions[6] = .{ .entry = 14, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 2, 0, 0, 0, 0, 2 } }, .result = 2 };
    const blocks = try allocator.alloc(ir.Block, readers.blocks.len + 1);
    @memcpy(blocks[0..readers.blocks.len], readers.blocks);
    blocks[11].instructions = &.{
        .{ .destination = 2, .opcode = .field, .operands = &.{1}, .immediate = 0 },
        .{ .destination = 3, .opcode = .field, .operands = &.{1}, .immediate = 1 },
        .{ .destination = 4, .opcode = .select, .operands = &.{ 0, 0, 2 } },
        .{ .destination = 5, .opcode = .product, .operands = &.{ 4, 3 } },
    };
    blocks[11].terminator = .{ .return_value = 5 };
    blocks[14] = .{ .function = 6, .instructions = &.{
        .{ .destination = 2, .opcode = .field, .operands = &.{1}, .immediate = 0 },
        .{ .destination = 3, .opcode = .field, .operands = &.{1}, .immediate = 1 },
        .{ .destination = 4, .opcode = .boolean_not, .operands = &.{2} },
        .{ .destination = 5, .opcode = .select, .operands = &.{ 0, 4, 2 } },
        .{ .destination = 6, .opcode = .product, .operands = &.{ 5, 3 } },
    }, .terminator = .{ .return_value = 6 } };
    const handlers = try allocator.dupe(ir.Handler, readers.handlers);
    handlers[0].return_function = 6;
    program.functions = functions;
    program.blocks = blocks;
    program.handlers = handlers;
    return program;
}

test "Reader fusion composes noncommuting pure returns in their original order" {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const base = try composedReturns(arena.allocator());
    for ([_]ir.Program{ base, try reverseReaderEffects(arena.allocator(), base) }) |original| {
        var candidate = (try data.reader_fusion.construct(a, original, .{})).?;
        defer candidate.deinit();
        try data.reader_fusion.validate(a, original, candidate.program, candidate.shape.site, .{});
        var fused = try data.reader_fusion.run(a, original, null, .{});
        defer fused.deinit();
        var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
        defer compiled.deinit();
        const borrows = try arena.allocator().alloc(data.borrow_contract.Summary, original.functions.len);
        for (borrows, 0..) |*summary, id| summary.* = .{ .function = id };
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = borrows };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "composed-readers", .object = encoded }}, &.{}, .{ .instance = "composed-readers", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        try std.testing.expectEqual(@as(usize, 1), compiled.program.handlers.len);
        try std.testing.expectEqual(@as(usize, 1), linked.program.handlers.len);
        for (0..2) |left| for (0..2) |right| for (0..2) |first| for (0..2) |second| {
            const input = [_]u8{ @intCast(left), @intCast(right), @intCast(first), @intCast(second) };
            const selected_first = if (first == 1) left else right;
            const selected_second = if (second == 1) left else right;
            const expected = [_]u8{ @intCast((selected_first | right) ^ left), @intCast(selected_second) };
            for ([_]ir.Program{ original, fused.program, compiled.program, linked.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &input }, .quantum = 1 });
                defer result.deinit();
                var steps: usize = 1;
                while (result.record == .progressed) {
                    try std.testing.expect(steps < 128);
                    const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = result.record.progressed.? }, .quantum = 1 });
                    result.deinit();
                    result = next;
                    steps += 1;
                }
                try std.testing.expect(result.record == .completed);
                try std.testing.expectEqualSlices(u8, &expected, result.record.completed);
            }
        };
        var wrong = candidate.program;
        const blocks = try arena.allocator().dupe(ir.Block, candidate.program.blocks);
        const start = original.blocks.len + 2;
        blocks[start].terminator.call.function = 6;
        blocks[start + 1].terminator.call.function = 3;
        wrong.blocks = blocks;
        var admitted = try data.activation_ownership.analyze(a, wrong);
        admitted.deinit();
        try std.testing.expectError(error.InvalidReaderFusion, data.reader_fusion.validate(a, original, wrong, candidate.shape.site, .{}));
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(wrong));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, wrong, bytes);
        var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{ 1, 1, 1, 1 } } });
        defer result.deinit();
        try std.testing.expect(result.record == .completed);
        try std.testing.expectEqualSlices(u8, &.{ 1, 1 }, result.record.completed); // Correct order yields {0,1}.
    }
}

test "mutable, shallow, scoped-body and cleanup handlers retain their images" {
    const boundary = @import("boundary");
    inline for (.{ boundary.source.examples.stateShared, boundary.source.examples.shallow, boundary.source.examples.scopedReader, boundary.source.examples.yieldingCleanup }) |example| {
        var builder = boundary.source.Builder.init(a);
        defer builder.deinit();
        var original = try boundary.program.compile(a, try example(&builder));
        defer original.deinit();
        var stats: data.reader_fusion.Statistics = .{};
        var retained = try data.reader_fusion.run(a, original.program, &stats, .{});
        defer retained.deinit();
        try std.testing.expectEqual(@as(usize, 0), stats.pairs_fused);
        try std.testing.expect(!stats.work_limit);
        try std.testing.expectEqual(try data.program_image.identity(a, original.program), try data.program_image.identity(a, retained.program));
    }
}
