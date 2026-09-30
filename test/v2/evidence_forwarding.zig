const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const p = data.program;
const a = std.testing.allocator;
const base = @import("tail_clauses.zig").administrative;
pub fn fixture(allocator: std.mem.Allocator) !ir.Program {
    var result = base;
    const functions = try allocator.alloc(ir.Function, 5);
    @memcpy(functions[0..4], base.functions);
    functions[4] = .{ .entry = 8, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 5, 5, 0, 0, 0 } }, .result = 0, .effects = &.{0} };
    const blocks = try allocator.alloc(ir.Block, 11);
    @memcpy(blocks[0..8], base.blocks);
    blocks[2].terminator = .{ .call = .{ .function = 4, .arguments = &.{ 1, 1, 0 }, .next = base.blocks[2].terminator.perform.next } };
    blocks[8] = .{ .function = 4, .instructions = &.{}, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 2, .next = .{ .block = 9, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } };
    blocks[9] = .{ .function = 4, .instructions = &.{}, .terminator = .{ .perform = .{ .effect = 0, .capability = 1, .payload = 3, .next = .{ .block = 10, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } };
    blocks[10] = .{ .function = 4, .instructions = &.{}, .terminator = .{ .return_value = 4 } };
    result.functions = functions;
    result.blocks = blocks;
    return result;
}
pub fn nestedFixture(allocator: std.mem.Allocator) !ir.Program {
    var program = try fixture(allocator);
    const schemas = try allocator.alloc(p.Schema, 7);
    @memcpy(schemas[0..6], program.schemas);
    schemas[4].internal.resumption.effects = &.{0};
    schemas[6] = .{ .internal = .{ .computation = .{ .parameters = &.{5}, .result = 0, .effects = &.{0}, .capture_bound = &.{ 0, 5 } } } };
    const functions = try allocator.alloc(ir.Function, 6);
    @memcpy(functions[0..5], program.functions);
    functions[0].layout.slots = &.{ 0, 3, 0, 0 };
    functions[0].effects = &.{0};
    functions[1].layout.slots = &.{ 0, 5, 0, 0, 6, 0 };
    functions[2].inputs = &.{ 0, 1 };
    functions[2].layout.slots = &.{ 0, 0 };
    functions[3].inputs = &.{ 4, 0, 1 };
    functions[3].layout.slots = &.{ 0, 4, 0, 0, 0 };
    functions[3].effects = &.{0};
    functions[5] = .{ .entry = 11, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 5, 0, 5, 0 } }, .result = 0, .effects = &.{0} };
    const blocks = try allocator.alloc(ir.Block, 13);
    @memcpy(blocks[0..11], program.blocks);
    blocks[0].instructions = &.{ .{ .destination = 3, .opcode = .constant, .immediate = 0 }, base.blocks[0].instructions[0] };
    blocks[0].terminator.handle.state = &.{3};
    blocks[2].instructions = &.{ .{ .destination = 5, .opcode = .constant, .immediate = 1 }, .{ .destination = 4, .opcode = .computation, .immediate = 1, .operands = &.{ 1, 0 } } };
    blocks[2].terminator = .{ .handle = .{ .handler = 0, .body = 4, .arguments = &.{}, .state = &.{5}, .next = base.blocks[2].terminator.perform.next } };
    blocks[4].terminator = .{ .return_value = 1 };
    blocks[5].terminator.resume_value.argument = 4;
    blocks[11] = .{ .function = 5, .instructions = &.{}, .terminator = .{ .call = .{ .function = 4, .arguments = &.{ 0, 2, 1 }, .next = .{ .block = 12, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } };
    blocks[12] = .{ .function = 5, .instructions = &.{}, .terminator = .{ .return_value = 3 } };
    const handlers = try allocator.dupe(ir.Handler, program.handlers);
    handlers[0].state = &.{0};
    handlers[0].effects = &.{0};
    program.schemas = schemas;
    program.functions = functions;
    program.blocks = blocks;
    program.handlers = handlers;
    program.constants = &.{ .{ .schema = 0, .bytes = &.{ 10, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 0, .bytes = &.{ 20, 0, 0, 0, 0, 0, 0, 0 } } };
    program.effects = &.{.{ .identity = "test.tail.admin", .payload = 0, .result = 0 }};
    program.constructors = try allocator.dupe(p.Constructor, &.{ program.constructors[0], .{ .function = 5, .capture = 1, .schema = 6 } });
    program.scopes.captures = try allocator.dupe(p.Capture, &.{ program.scopes.captures[0], .{ .fields = &.{ 5, 0 }, .use = .reusable } });
    return program;
}

test "World distinguishes actual installations while checked forwarding removes duplicate arguments" {
    for ([_]bool{ false, true }) |nested| {
        var arena = std.heap.ArenaAllocator.init(a);
        defer arena.deinit();
        const original = if (nested) try nestedFixture(arena.allocator()) else try fixture(arena.allocator());
        var stats: data.evidence_forwarding.Statistics = .{};
        var selected = try data.evidence_forwarding.run(a, original, &stats, .{});
        defer selected.deinit();
        try std.testing.expectEqual(@as(usize, if (nested) 0 else 1), stats.parameters_coalesced);
        var compiled = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
        defer compiled.deinit();
        const borrows = try arena.allocator().alloc(data.borrow_contract.Summary, original.functions.len);
        for (borrows, 0..) |*summary, id| summary.* = .{ .function = id };
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = borrows };
        const encoded = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(encoded);
        _ = try data.component.encode(a, object, encoded);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "evidence", .object = encoded }}, &.{}, .{ .instance = "evidence", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        var forged = original;
        const blocks = try arena.allocator().dupe(ir.Block, original.blocks);
        blocks[9].terminator.perform.capability = 0;
        forged.blocks = blocks;
        if (nested) {
            var admitted = try data.activation_ownership.analyze(a, forged);
            admitted.deinit();
            try std.testing.expectError(error.InvalidEvidenceForwarding, data.evidence_forwarding.validate(a, original, forged, &.{.{ .function = 4, .keep = 0, .remove = 1 }}, 10_000_000));
        }
        const programs = [_]ir.Program{ original, selected.program, compiled.program, linked.program, forged };
        for ([_]u64{ 0, 7, std.math.maxInt(u64) }) |input| for (programs[0..if (nested) 5 else 4], 0..) |program, arm| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var args: [8]u8 = undefined;
            std.mem.writeInt(u64, &args, input, .little);
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args }, .quantum = 1 });
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
            const value: u64 = if (nested) (if (arm == 4) 10 else 20) else input;
            var expected: [8]u8 = undefined;
            std.mem.writeInt(u64, &expected, ~value, .little);
            try std.testing.expectEqualSlices(u8, &expected, result.record.completed);
            std.debug.print("evidence nested={any} arm={d} bytes={d} steps={d}\n", .{ nested, arm, bytes.len, steps });
        };
    }
}
