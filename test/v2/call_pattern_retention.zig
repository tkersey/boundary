const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const ir = data.activation;
const callable: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{
        .u64,                                                                                                                                        .unit,                                 .boolean,
        .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{2}, .use = .reusable } } },                        .{ .internal = .{ .capability = 0 } }, .{ .internal = .{ .resumption = .{ .effect = 0, .input = 1, .answer = 0, .handled = &.{0}, .capture_bound = &.{ 0, 1, 3, 4 }, .mode = .deep, .use = .linear } } },
        .{ .internal = .{ .computation = .{ .parameters = &.{4}, .result = 0, .effects = &.{0}, .capture_bound = &.{ 0, 2 }, .use = .reusable } } },
    },
    .constants = &.{ .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } }, .{ .schema = 1, .bytes = &.{} } },
    .effects = &.{.{ .identity = "review", .payload = 1, .result = 1, .external = false }},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 2, 0, 6, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 2, 0, 4, 3, 0 } }, .result = 0, .effects = &.{0} },
        .{ .entry = 4, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 3, 4, 0, 1, 0, 2 } }, .result = 0, .effects = &.{0} },
        .{ .entry = 9, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 2, 0, 0 } }, .result = 0 },
        .{ .entry = 12, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
        .{ .entry = 13, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 1, 5, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 2, .opcode = .computation, .operands = &.{ 0, 1 }, .immediate = 1 }}, .terminator = .{ .handle = .{ .handler = 0, .body = 2, .arguments = &.{}, .state = &.{}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 3, .opcode = .computation, .operands = &.{0}, .immediate = 0 }}, .terminator = .{ .call = .{ .function = 2, .arguments = &.{ 3, 2, 1 }, .next = .{ .block = 3, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
        .{ .function = 2, .instructions = &.{ .{ .destination = 4, .opcode = .constant, .immediate = 0 }, .{ .destination = 5, .opcode = .equal, .operands = &.{ 2, 4 } } }, .terminator = .{ .branch = .{ .condition = 5, .when_true = .{ .block = 8 }, .when_false = .{ .block = 5 } } } },
        .{ .function = 2, .instructions = &.{.{ .destination = 3, .opcode = .constant, .immediate = 1 }}, .terminator = .{ .perform = .{ .effect = 0, .capability = 1, .payload = 3, .next = .{ .block = 6 } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 0, .arguments = &.{2}, .next = .{ .block = 7, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .call = .{ .function = 2, .arguments = &.{ 0, 1, 4 }, .next = .{ .block = 8, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
        .{ .function = 3, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 0, .when_true = .{ .block = 10 }, .when_false = .{ .block = 11 } } } },
        .{ .function = 3, .instructions = &.{.{ .destination = 2, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .return_value = 2 } },
        .{ .function = 3, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
        .{ .function = 4, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 5, .instructions = &.{}, .terminator = .{ .resume_value = .{ .resumption = 1, .argument = 0, .next = .{ .block = 14, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 5, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
    },
    .scopes = .{ .captures = &.{ .{ .fields = &.{2}, .use = .reusable }, .{ .fields = &.{ 2, 0 }, .use = .reusable } } },
    .constructors = &.{ .{ .function = 3, .capture = 0, .schema = 3 }, .{ .function = 1, .capture = 1, .schema = 6 } },
    .handlers = &.{.{ .mode = .deep, .input = 0, .answer = 0, .return_function = 4, .clauses = &.{.{ .effect = 0, .function = 5, .resumption = 5 }} }},
};
const variant: ir.Program = .{ .roots = .{ .entry = 0, .result = 0, .failure = 2 }, .schemas = &.{ .u64, .boolean, .unit, .{ .sum = &.{0} }, .{ .internal = .{ .capability = 0 } }, .{ .internal = .{ .resumption = .{ .effect = 0, .input = 2, .answer = 0, .handled = &.{0}, .capture_bound = &.{ 1, 3, 4 }, .mode = .deep, .use = .linear } } }, .{ .internal = .{ .computation = .{ .parameters = &.{4}, .result = 0, .effects = &.{0}, .capture_bound = &.{ 0, 1 }, .use = .reusable } } } }, .constants = &.{ .{ .schema = 1, .bytes = &.{1} }, .{ .schema = 2, .bytes = &.{} } }, .effects = &.{.{ .identity = "retained variant", .payload = 2, .result = 2, .external = false }}, .functions = &.{ .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 1, 3, 6, 0 } }, .result = 0 }, .{ .entry = 2, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 1, 4, 3, 0 } }, .result = 0, .effects = &.{0} }, .{ .entry = 4, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 3, 1, 4, 1, 2, 0 } }, .result = 0, .effects = &.{0} }, .{ .entry = 9, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 }, .{ .entry = 10, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 2, 5, 0 } }, .result = 0 } }, .blocks = &.{ .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .computation, .operands = &.{ 0, 1 } }}, .terminator = .{ .handle = .{ .handler = 0, .body = 3, .arguments = &.{}, .state = &.{}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } }, .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } }, .{ .function = 1, .instructions = &.{.{ .destination = 3, .opcode = .variant, .operands = &.{0} }}, .terminator = .{ .call = .{ .function = 2, .arguments = &.{ 3, 1, 2 }, .next = .{ .block = 3, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } }, .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 4 } }, .{ .function = 2, .instructions = &.{}, .terminator = .{ .branch = .{ .condition = 1, .when_true = .{ .block = 5 }, .when_false = .{ .block = 7 } } } }, .{ .function = 2, .instructions = &.{.{ .destination = 4, .opcode = .constant, .immediate = 1 }}, .terminator = .{ .perform = .{ .effect = 0, .capability = 2, .payload = 4, .next = .{ .block = 6 } } } }, .{ .function = 2, .instructions = &.{.{ .destination = 5, .opcode = .variant_payload, .operands = &.{0}, .failures = &.{.{ .kind = .invalid_variant, .value = 1 }} }}, .terminator = .{ .return_value = 5 } }, .{ .function = 2, .instructions = &.{.{ .destination = 3, .opcode = .constant }}, .terminator = .{ .call = .{ .function = 2, .arguments = &.{ 0, 3, 2 }, .next = .{ .block = 8, .assignments = &.{.{ .destination = 5, .source = .returned }} } } } }, .{ .function = 2, .instructions = &.{}, .terminator = .{ .return_value = 5 } }, .{ .function = 3, .instructions = &.{}, .terminator = .{ .return_value = 0 } }, .{ .function = 4, .instructions = &.{}, .terminator = .{ .resume_value = .{ .resumption = 1, .argument = 0, .next = .{ .block = 11, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } }, .{ .function = 4, .instructions = &.{}, .terminator = .{ .return_value = 2 } } }, .scopes = .{ .captures = &.{.{ .fields = &.{ 0, 1 }, .use = .reusable }} }, .constructors = &.{.{ .function = 1, .capture = 0, .schema = 6 }}, .handlers = &.{.{ .mode = .deep, .input = 0, .answer = 0, .return_function = 3, .clauses = &.{.{ .effect = 0, .function = 4, .resumption = 5 }} }} };

pub const Case = enum { callable, callable_compatible, callable_indirect, callable_after, callable_multiple, callable_multiple_compatible, variant, variant_compatible, variant_indirect, variant_after };
pub fn isCallable(case: Case) bool {
    return switch (case) {
        .callable, .callable_compatible, .callable_indirect, .callable_after, .callable_multiple, .callable_multiple_compatible => true,
        else => false,
    };
}
pub fn fixture(a: std.mem.Allocator, case: Case) !ir.Program {
    const callable_case = isCallable(case);
    const base = if (callable_case) callable else variant;
    const indirect = case == .callable_indirect or case == .variant_indirect;
    var result = base;
    const functions = try a.alloc(ir.Function, base.functions.len + @intFromBool(indirect));
    @memcpy(functions[0..base.functions.len], base.functions);
    const blocks = try a.alloc(ir.Block, base.blocks.len + if (indirect) @as(usize, 2) else 0);
    @memcpy(blocks[0..base.blocks.len], base.blocks);
    result.functions = functions;
    result.blocks = blocks;
    if (case == .callable_compatible or case == .variant_compatible) {
        const schemas = try a.dupe(data.program.Schema, base.schemas);
        schemas[5].internal.resumption.capture_bound = if (callable_case) &.{ 0, 1, 2, 3, 4 } else &.{ 0, 1, 3, 4 };
        result.schemas = schemas;
    }
    if (case == .callable_multiple or case == .callable_multiple_compatible) {
        const schemas = try a.dupe(data.program.Schema, base.schemas);
        schemas[3].internal.computation.capture_bound = &.{ 1, 2 };
        schemas[5].internal.resumption.capture_bound = if (case == .callable_multiple) &.{ 0, 2, 3, 4 } else &.{ 0, 1, 2, 3, 4 };
        result.schemas = schemas;
        const captures = try a.dupe(data.program.Capture, base.scopes.captures);
        captures[0].fields = &.{ 2, 1 };
        result.scopes.captures = captures;
        functions[1].layout.slots = &.{ 2, 0, 4, 3, 0, 1 };
        functions[3].inputs = &.{ 0, 3, 1 };
        functions[3].layout.slots = &.{ 2, 0, 0, 1 };
        blocks[2].instructions = &.{ .{ .destination = 5, .opcode = .constant, .immediate = 1 }, .{ .destination = 3, .opcode = .computation, .operands = &.{ 0, 5 }, .immediate = 0 } };
    }
    if (indirect) {
        const unit: data.program.Id = if (callable_case) 1 else 2;
        const layout = try a.dupe(data.program.Id, &.{ 4, unit, unit });
        const function = base.functions.len;
        const first = base.blocks.len;
        functions[function] = .{ .entry = first, .inputs = &.{ 0, 1 }, .layout = .{ .slots = layout }, .result = unit, .effects = &.{0} };
        blocks[first] = .{ .function = function, .instructions = &.{}, .terminator = .{ .perform = .{ .effect = 0, .capability = 0, .payload = 1, .next = .{ .block = first + 1, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } };
        blocks[first + 1] = .{ .function = function, .instructions = &.{}, .terminator = .{ .return_value = 2 } };
        const perform = blocks[5].terminator.perform;
        blocks[5].terminator = .{ .call = .{ .function = function, .arguments = try a.dupe(data.program.Id, &.{ perform.capability.?, perform.payload }), .next = perform.next } };
    }
    if (case == .callable_after) {
        const perform = blocks[5].terminator.perform;
        blocks[5].terminator = blocks[6].terminator;
        blocks[5].terminator.apply.next.block = 6;
        blocks[6].terminator = blocks[7].terminator;
        blocks[6].terminator.call.next.block = 7;
        blocks[7].terminator = .{ .perform = perform };
        blocks[7].terminator.perform.next.block = 8;
    }
    if (case == .variant_after) {
        // The selected sum is consumed before the effect. Its result is dead;
        // a fresh scalar is produced afterward, so no payload crosses the bound.
        blocks[5].instructions = try a.dupe(ir.Instruction, &.{ base.blocks[5].instructions[0], base.blocks[6].instructions[0] });
        const constants = try a.alloc(data.program.Literal, base.constants.len + 1);
        @memcpy(constants[0..base.constants.len], base.constants);
        constants[base.constants.len] = .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } };
        result.constants = constants;
        blocks[6].instructions = try a.dupe(ir.Instruction, &.{.{ .destination = 5, .opcode = .constant, .immediate = base.constants.len }});
    }
    return result;
}

pub fn argsFor(case: Case, word: u64, flag: bool) [9]u8 {
    var args: [9]u8 = undefined;
    if (isCallable(case)) {
        args[0] = @intFromBool(flag);
        std.mem.writeInt(u64, args[1..9], word, .little);
    } else {
        std.mem.writeInt(u64, args[0..8], word, .little);
        args[8] = @intFromBool(flag);
    }
    return args;
}

pub fn linked(a: std.mem.Allocator, original: ir.Program) !data.linker.Linked {
    const borrows = try a.alloc(data.borrow_contract.Summary, original.functions.len);
    defer a.free(borrows);
    for (borrows, 0..) |*summary, id| summary.* = .{ .function = id };
    const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = original.roots.entry } }}, .borrows = borrows };
    const encoded = try a.alloc(u8, try data.component.encodedLength(object));
    defer a.free(encoded);
    _ = try data.component.encode(a, object, encoded);
    const result = try data.linker.linkWithCompilation(a, &.{.{ .key = "retention", .object = encoded }}, &.{}, .{ .instance = "retention", .symbol = "main" }, .{ .contract = .semantic });
    @memset(encoded, 0xff);
    return result;
}

test "argument specialization preserves retained-schema execution and source-free linking" {
    const a = std.testing.allocator;
    inline for (@typeInfo(Case).@"enum".field_values) |field_value| {
        const case: Case = @fromBackingInt(@intCast(field_value));
        var arena = std.heap.ArenaAllocator.init(a);
        defer arena.deinit();
        const original = try fixture(arena.allocator(), case);
        var selected = false;
        if (try data.call_patterns.construct(a, original, .{})) |value| {
            var candidate = value;
            defer candidate.deinit();
            for (candidate.variants) |item| if (item.key.function == 2 and item.key.parameter == 0) {
                selected = true;
            };
        }
        const eligible = case == .callable_compatible or case == .callable_multiple_compatible or case == .variant_compatible or case == .callable_after or case == .variant_after;
        try std.testing.expectEqual(eligible, selected);
        var baseline = try data.closed_compilation.run(a, original, .{});
        defer baseline.deinit();
        var checked = try data.call_patterns.run(a, original, null, .{});
        defer checked.deinit();
        var semantic = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
        defer semantic.deinit();
        var object = try linked(a, original);
        defer object.deinit();
        for ([_]u64{ 0, 1, 0xffffffffffffffff }) |word| for ([_]bool{ false, true }) |flag| {
            const args = argsFor(case, word, flag);
            const divergent = isCallable(case) and !flag and word != 0;
            var expected: [8]u8 = undefined;
            std.mem.writeInt(u64, &expected, if (isCallable(case) or case == .variant_after) 0 else word, .little);
            for ([_]ir.Program{ baseline.program, checked.program, semantic.program, object.program }) |program| {
                const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
                defer a.free(bytes);
                _ = try data.program_image.encode(a, program, bytes);
                var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args }, .quantum = 1 });
                defer outcome.deinit();
                var steps: usize = 1;
                while (outcome.record == .progressed and steps < 128) {
                    const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = outcome.record.progressed.? }, .quantum = 1 });
                    outcome.deinit();
                    outcome = next;
                    steps += 1;
                }
                if (divergent) {
                    try std.testing.expect(outcome.record == .progressed);
                } else {
                    try std.testing.expect(outcome.record == .completed);
                    try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
                }
            }
        };
    }
}
