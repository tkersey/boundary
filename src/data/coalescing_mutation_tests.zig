// Copyright (c) 2026 Boundary contributors. MIT license.
//! Well-typed semantic mutants: ordinary admission is deliberately insufficient.
const std = @import("std");
const testing = std.testing;
const p = @import("program.zig");
const ir = @import("activation.zig");
const r = @import("relocation.zig");
const w = @import("coalescing_witness.zig");
const validator = @import("coalescing_validation.zig");
const admission = @import("activation_ownership.zig");
const pass = @import("coalescing.zig");

fn admitted(program: ir.Program) !void {
    var facts = try admission.analyze(testing.allocator, program);
    facts.deinit();
}
fn identity(a: std.mem.Allocator, program: ir.Program) !w.Witness {
    const maps = try r.identityMaps(a, try r.sizes(program));
    const locals = try a.alloc(w.Local, program.functions.len);
    for (locals, program.functions) |*local, function| {
        const slots = try a.alloc(p.Id, function.layout.slots.len);
        const custody = try a.alloc(p.Id, function.custody.len);
        for (slots, 0..) |*id, index| id.* = index;
        for (custody, 0..) |*id, index| id.* = index;
        local.* = .{ .slots = slots, .custody = custody };
    }
    return .{ .representatives = maps, .final = maps, .locals = locals };
}
fn rejectMutation(before: ir.Program, after: ir.Program) !void {
    try admitted(before);
    try admitted(after);
    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    const map = try identity(scratch.allocator(), before);
    try validator.validate(testing.allocator, before, before, map);
    try testing.expectError(error.InvalidCorrespondence, validator.validate(testing.allocator, before, after, map));
}

const arithmetic: ir.Program = .{
    .roots = .{ .entry = 2, .result = 1, .failure = 0 },
    .schemas = &.{ .u64, .{ .product = &.{ 0, 0 } } },
    .constants = &.{
        .{ .schema = 0, .bytes = &.{ 41, 0, 0, 0, 0, 0, 0, 0 } },
        .{ .schema = 0, .bytes = &.{ 42, 0, 0, 0, 0, 0, 0, 0 } },
    },
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 },
        .{ .entry = 1, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0, 0, 1 } }, .result = 1 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{
            .destination = 2,
            .opcode = .integer_add,
            .operands = &.{ 0, 1 },
            .failures = &.{.{ .kind = .arithmetic_overflow, .value = 0 }},
        }}, .terminator = .{ .return_value = 2 } },
        .{ .function = 1, .instructions = &.{.{
            .destination = 2,
            .opcode = .integer_add,
            .operands = &.{ 0, 1 },
            .failures = &.{.{ .kind = .arithmetic_overflow, .value = 0 }},
        }}, .terminator = .{ .return_value = 2 } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .call = .{
            .function = 0,
            .arguments = &.{ 0, 1 },
            .next = .{
                .block = 3,
                .assignments = &.{.{ .destination = 2, .source = .returned }},
            },
        } } },
        .{ .function = 2, .instructions = &.{}, .terminator = .{ .call = .{
            .function = 1,
            .arguments = &.{ 0, 1 },
            .next = .{
                .block = 4,
                .assignments = &.{.{ .destination = 3, .source = .returned }},
            },
        } } },
        .{ .function = 2, .instructions = &.{.{
            .destination = 4,
            .opcode = .product,
            .operands = &.{ 2, 3 },
        }}, .terminator = .{ .return_value = 4 } },
    },
};

test "coalescing rejects changed arithmetic opcode operands and failure payload independently" {
    var equivalent = try pass.run(testing.allocator, arithmetic, .{ .mode = .safe });
    defer equivalent.deinit();
    try testing.expectEqual(@as(usize, 2), equivalent.program.functions.len);
    const Mutation = enum { opcode, operands, failure_payload, returned_slot };
    for (std.enums.values(Mutation)) |mutation| {
        var changed = arithmetic;
        var blocks = arithmetic.blocks[0..5].*;
        var instructions = arithmetic.blocks[1].instructions[0..1].*;
        switch (mutation) {
            .opcode => instructions[0].opcode = .integer_sub,
            .operands => instructions[0].operands = &.{ 1, 0 },
            .failure_payload => instructions[0].failures =
                &.{.{ .kind = .arithmetic_overflow, .value = 1 }},
            .returned_slot => blocks[1].terminator.return_value = 0,
        }
        blocks[1].instructions = &instructions;
        changed.blocks = &blocks;
        try rejectMutation(arithmetic, changed);
        var result = try pass.run(testing.allocator, changed, .{ .mode = .safe });
        defer result.deinit();
        try testing.expectEqual(@as(usize, 3), result.program.functions.len);
    }
}

test "coalescing raw checker distinguishes immediate ordinals and complete failure kinds" {
    const field: ir.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 0 },
        .schemas = arithmetic.schemas,
        .constants = &.{},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 1, 0 } }, .result = 0 }},
        .blocks = &.{.{ .function = 0, .instructions = &.{.{
            .destination = 1,
            .opcode = .field,
            .operands = &.{0},
            .immediate = 0,
        }}, .terminator = .{ .return_value = 1 } }},
    };
    var changed = field;
    var blocks = field.blocks[0..1].*;
    var operations = blocks[0].instructions[0..1].*;
    operations[0].immediate = 1;
    blocks[0].instructions = &operations;
    changed.blocks = &blocks;
    try rejectMutation(field, changed);

    var division = arithmetic;
    var div_blocks = arithmetic.blocks[0..5].*;
    var div_operations = arithmetic.blocks[1].instructions[0..1].*;
    div_operations[0].opcode = .integer_div;
    div_operations[0].failures = &.{
        .{ .kind = .arithmetic_overflow, .value = 0 },
        .{ .kind = .division_by_zero, .value = 1 },
    };
    div_blocks[1].instructions = &div_operations;
    division.blocks = &div_blocks;
    try admitted(division);
    var mutant_blocks = div_blocks;
    var mutant_operations = div_operations;
    mutant_operations[0].failures = &.{
        .{ .kind = .arithmetic_overflow, .value = 1 },
        .{ .kind = .division_by_zero, .value = 0 },
    };
    mutant_blocks[1].instructions = &mutant_operations;
    var mutant = division;
    mutant.blocks = &mutant_blocks;
    try rejectMutation(division, mutant);
}

test "coalescing raw checker rejects swapped branch and sum-case roles" {
    for ([_]bool{ false, true }) |sum| {
        const program: ir.Program = .{
            .roots = .{ .entry = 0, .result = 0, .failure = 0 },
            .schemas = &.{ .u64, if (sum) .{ .sum = &.{ 0, 0 } } else .boolean },
            .constants = arithmetic.constants,
            .effects = &.{},
            .functions = &.{.{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 1, 0 } }, .result = 0 }},
            .blocks = &.{
                .{ .function = 0, .instructions = &.{}, .terminator = if (sum)
                    .{ .switch_variant = .{ .value = 0, .cases = &.{ .{ .block = 1 }, .{ .block = 2 } } } }
                else
                    .{ .branch = .{ .condition = 0, .when_true = .{ .block = 1 }, .when_false = .{ .block = 2 } } } },
                .{ .function = 0, .instructions = &.{.{
                    .destination = 1,
                    .opcode = .constant,
                    .immediate = 0,
                }}, .terminator = .{ .return_value = 1 } },
                .{ .function = 0, .instructions = &.{.{
                    .destination = 1,
                    .opcode = .constant,
                    .immediate = 1,
                }}, .terminator = .{ .return_value = 1 } },
            },
        };
        var changed = program;
        var blocks = program.blocks[0..3].*;
        blocks[0].terminator = if (sum) .{ .switch_variant = .{
            .value = 0,
            .cases = &.{ .{ .block = 2 }, .{ .block = 1 } },
        } } else .{ .branch = .{
            .condition = 0,
            .when_true = .{ .block = 2 },
            .when_false = .{ .block = 1 },
        } };
        changed.blocks = &blocks;
        try rejectMutation(program, changed);
    }
}

test "coalescing rejects changed nominal effect use and forged many-to-one effect maps" {
    const program: ir.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 0 },
        .schemas = &.{.u64},
        .constants = &.{},
        .effects = &.{
            .{ .identity = "same-name", .payload = 0, .result = 0 },
            .{ .identity = "same-name", .payload = 0, .result = 0 },
        },
        .functions = &.{.{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0, .effects = &.{ 0, 1 } }},
        .blocks = &.{
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .perform = .{
                .effect = 0,
                .payload = 0,
                .next = .{ .block = 1, .assignments = &.{.{ .destination = 1, .source = .returned }} },
            } } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .perform = .{
                .effect = 1,
                .payload = 1,
                .next = .{ .block = 2, .assignments = &.{.{ .destination = 1, .source = .returned }} },
            } } },
            .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
        },
    };
    var changed = program;
    var blocks = program.blocks[0..3].*;
    blocks[0].terminator.perform.effect = 1;
    changed.blocks = &blocks;
    try rejectMutation(program, changed);
    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    var forged = try identity(scratch.allocator(), program);
    forged.representatives[@intFromEnum(r.Kind.effect)] = &.{ 0, 0 };
    forged.final[@intFromEnum(r.Kind.effect)] = &.{ 0, 0 };
    try testing.expectError(error.InvalidCorrespondence, validator.validate(testing.allocator, program, program, forged));
    var optimized = try pass.run(testing.allocator, program, .{ .mode = .safe });
    defer optimized.deinit();
    try testing.expectEqual(@as(usize, 2), optimized.program.effects.len);
    try testing.expectEqual(@as(p.Id, 0), optimized.program.blocks[0].terminator.perform.effect);
    try testing.expectEqual(@as(p.Id, 1), optimized.program.blocks[1].terminator.perform.effect);
}

test "coalescing does not erase same-shaped code type width sign bound or tag contracts" {
    const pairs = [_][2]p.Schema{
        .{ .u32, .i32 },                                                                                 .{ .u32, .u64 },
        .{ .{ .bounded_bytes = 8 }, .{ .bounded_bytes = 9 } },                                           .{ .{ .bounded_text = 8 }, .{ .bounded_text = 9 } },
        .{ .{ .array = .{ .element = 4, .length = 1 } }, .{ .array = .{ .element = 4, .length = 2 } } }, .{ .{ .enumeration = &.{ 0, 1 } }, .{ .enumeration = &.{ 0, 2 } } },
    };
    for (pairs) |pair| {
        const schemas = [_]p.Schema{ pair[0], pair[1], .{ .product = &.{ 0, 1 } }, .unit, .u8 };
        const program: ir.Program = .{
            .roots = .{ .entry = 2, .result = 2, .failure = 3 },
            .schemas = &schemas,
            .constants = &.{},
            .effects = &.{},
            .functions = &.{
                .{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
                .{ .entry = 1, .inputs = &.{0}, .layout = .{ .slots = &.{1} }, .result = 1 },
                .{ .entry = 2, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 1, 0, 1, 2 } }, .result = 2 },
            },
            .blocks = &.{
                .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
                .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
                .{ .function = 2, .instructions = &.{}, .terminator = .{ .call = .{
                    .function = 0,
                    .arguments = &.{0},
                    .next = .{ .block = 3, .assignments = &.{.{ .destination = 2, .source = .returned }} },
                } } },
                .{ .function = 2, .instructions = &.{}, .terminator = .{ .call = .{
                    .function = 1,
                    .arguments = &.{1},
                    .next = .{ .block = 4, .assignments = &.{.{ .destination = 3, .source = .returned }} },
                } } },
                .{ .function = 2, .instructions = &.{.{
                    .opcode = .product,
                    .destination = 4,
                    .operands = &.{ 2, 3 },
                }}, .terminator = .{ .return_value = 4 } },
            },
        };
        var result = try pass.run(testing.allocator, program, .{ .mode = .safe });
        defer result.deinit();
        try testing.expectEqual(@as(usize, 3), result.program.functions.len);
        const first = result.program.schemas[@intCast(result.program.functions[0].result)];
        const second = result.program.schemas[@intCast(result.program.functions[1].result)];
        try testing.expect(!@import("record.zig").equal(p.Schema, first, second));
    }
}
