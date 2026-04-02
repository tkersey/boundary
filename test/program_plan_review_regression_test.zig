const effect_ir = @import("effect_ir");
const internal_program_plan = @import("internal_program_plan");
const std = @import("std");

test "planFromProgram emits return_unit for row-only leaf programs" {
    const row = effect_ir.rowFromSpec(.{
        .writer = .{
            .tell = effect_ir.Transform([]const u8, void),
        },
    });
    const program = effect_ir.Program{
        .functions = &.{.{
            .symbol = .{
                .module_path = "examples/open_row_state_writer.zig",
                .symbol_name = "runBody",
            },
            .row = row,
            .outputs = &.{.{ .label = "writer", .OutputType = [][]const u8 }},
        }},
        .call_edges = &.{},
    };

    const plan = comptime try internal_program_plan.planFromProgram("example.open_row_state_writer", program);

    try std.testing.expectEqual(@as(usize, 0), plan.locals.len);
    try std.testing.expectEqual(@as(usize, 0), plan.instructions.len);
    try std.testing.expectEqual(internal_program_plan.TerminatorKind.return_unit, plan.terminators[0].kind);
    try plan.validate();
}

test "planFromProgram keeps row-only helper calls self-contained without synthetic returns" {
    comptime {
        @setEvalBranchQuota(20_000);
    }
    const shared_row = effect_ir.rowFromSpec(.{
        .state = .{
            .get = effect_ir.Transform(void, i32),
        },
    });
    const helper_symbol = effect_ir.SymbolRef{
        .module_path = "examples/workflow.zig",
        .symbol_name = "helper",
    };
    const root_symbol = effect_ir.SymbolRef{
        .module_path = "examples/workflow.zig",
        .symbol_name = "root",
    };
    const program = effect_ir.Program{
        .functions = &.{
            .{
                .symbol = root_symbol,
                .row = shared_row,
                .outputs = &.{.{ .label = "state", .OutputType = i32 }},
            },
            .{
                .symbol = helper_symbol,
                .row = shared_row,
                .outputs = &.{.{ .label = "state", .OutputType = i32 }},
            },
        },
        .call_edges = &.{.{
            .caller = root_symbol,
            .callee = helper_symbol,
        }},
    };

    const plan = comptime try internal_program_plan.planFromProgram("example.workflow", program);

    try std.testing.expectEqual(@as(usize, 1), plan.instructions.len);
    try std.testing.expectEqual(@as(u16, 0), plan.functions[0].first_instruction);
    try std.testing.expectEqual(@as(u16, 1), plan.functions[0].instruction_count);
    try std.testing.expectEqual(@as(u16, 1), plan.functions[1].first_instruction);
    try std.testing.expectEqual(@as(u16, 0), plan.functions[1].instruction_count);
    try std.testing.expectEqual(internal_program_plan.InstructionKind.call_helper, plan.instructions[0].kind);
    try std.testing.expectEqual(internal_program_plan.TerminatorKind.return_unit, plan.terminators[0].kind);
    try std.testing.expectEqual(internal_program_plan.TerminatorKind.return_unit, plan.terminators[1].kind);
    try plan.validate();
}

test "planFromProgram forwards row-only helper parameters through synthesized call_arg spans" {
    const shared_row = effect_ir.rowFromSpec(.{});
    const helper_symbol = effect_ir.SymbolRef{
        .module_path = "examples/workflow.zig",
        .symbol_name = "helper",
    };
    const root_symbol = effect_ir.SymbolRef{
        .module_path = "examples/workflow.zig",
        .symbol_name = "root",
    };
    const program = effect_ir.Program{
        .functions = &.{
            .{
                .symbol = root_symbol,
                .row = shared_row,
                .parameter_codecs = &.{.i32},
                .ValueType = i32,
            },
            .{
                .symbol = helper_symbol,
                .row = shared_row,
                .parameter_codecs = &.{.i32},
                .ValueType = i32,
            },
        },
        .call_edges = &.{.{
            .caller = root_symbol,
            .callee = helper_symbol,
        }},
    };

    const plan = comptime try internal_program_plan.planFromProgram("example.row_only_helper_value", program);

    try std.testing.expectEqual(@as(usize, 3), plan.locals.len);
    try std.testing.expectEqual(@as(usize, 1), plan.call_args.len);
    try std.testing.expectEqual(@as(u16, 2), plan.functions[0].local_count);
    try std.testing.expectEqual(@as(u16, 1), plan.functions[1].local_count);
    try std.testing.expectEqual(@as(u16, 1), plan.instructions[0].dst);
    try std.testing.expectEqual(@as(u16, 0), plan.instructions[0].aux);
    try std.testing.expectEqual(@as(u16, 0), plan.call_args[0]);
    try std.testing.expectEqual(@as(u16, 1), plan.instructions[1].operand);
    try std.testing.expectEqual(@as(u16, 0), plan.instructions[2].operand);
    try plan.validate();
}

test "planFromProgram preserves row-only parameter returns inside the function local span" {
    const program = effect_ir.Program{
        .functions = &.{.{
            .symbol = .{
                .module_path = "examples/identity.zig",
                .symbol_name = "identity",
            },
            .row = effect_ir.rowFromSpec(.{}),
            .parameter_codecs = &.{.bool},
            .ValueType = bool,
        }},
        .call_edges = &.{},
    };

    const plan = comptime try internal_program_plan.planFromProgram("example.row_only_param_return", program);

    try std.testing.expectEqual(@as(usize, 1), plan.locals.len);
    try std.testing.expectEqual(@as(u16, 1), plan.functions[0].local_count);
    try std.testing.expectEqual(internal_program_plan.InstructionKind.return_value, plan.instructions[0].kind);
    try std.testing.expectEqual(@as(u16, 0), plan.instructions[0].operand);
    try plan.validate();
}
