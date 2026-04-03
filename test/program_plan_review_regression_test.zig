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

test "planFromProgram rejects ambiguous row-only multi-parameter returns without explicit bodies" {
    const program = effect_ir.Program{
        .functions = &.{.{
            .symbol = .{
                .module_path = "examples/pick.zig",
                .symbol_name = "pick",
            },
            .row = effect_ir.rowFromSpec(.{}),
            .parameter_codecs = &.{ .bool, .bool },
            .ValueType = bool,
        }},
        .call_edges = &.{},
    };

    const result = comptime internal_program_plan.planFromProgram("example.row_only_ambiguous_param_return", program);
    try std.testing.expectError(error.InvalidProgramBodyShape, result);
}

test "ProgramPlan.validate rejects helper call arguments whose codecs disagree with the callee parameters" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "invalid.helper_call_arg_codec",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "root",
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 1,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .unit,
                .parameter_count = 1,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 1,
                .local_count = 1,
                .first_block = 1,
                .block_count = 1,
                .first_instruction = 1,
                .instruction_count = 0,
            },
        },
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .bool },
        },
        .call_args = &.{0},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 1,
                .instruction_count = 0,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .return_unit },
            .{ .kind = .return_unit },
        },
        .instructions = &.{.{
            .kind = .call_helper,
            .operand = 1,
            .aux = 0,
        }},
    };

    try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
}

test "ProgramPlan.validate rejects payload-bearing call_op instructions without a payload local" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "invalid.call_op_missing_payload_local",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{.{
            .label = "req",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "call",
            .mode = .transform,
            .payload_codec = .i32,
            .resume_codec = .unit,
        }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{
            .kind = .call_op,
            .dst = 0,
            .operand = 0,
            .aux = std.math.maxInt(u16),
        }},
    };

    try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
}

test "ProgramPlan.validate rejects payload-bearing call_op instructions whose payload local codec disagrees with the op" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "invalid.call_op_payload_codec",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{.{
            .label = "req",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "call",
            .mode = .transform,
            .payload_codec = .i32,
            .resume_codec = .unit,
        }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .bool }},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{
            .kind = .call_op,
            .operand = 0,
            .aux = 0,
        }},
    };

    try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
}

test "ProgramPlan.validate rejects return_unit terminators for value-returning functions" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "invalid.return_unit_value_function",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 1,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{.{ .label = "result", .codec = .i32 }},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 0,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    try std.testing.expectError(error.InvalidTerminatorInstruction, plan.validate());
}

test "ProgramPlan.validate rejects return_value terminators for unit-returning functions" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "invalid.return_value_unit_function",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{.{
            .kind = .return_value,
            .operand = 0,
        }},
    };

    try std.testing.expectError(error.InvalidTerminatorInstruction, plan.validate());
}

test "ProgramPlan.validate rejects return_value instructions whose local codec disagrees with the function value codec" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "invalid.return_value_codec",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{.{
            .kind = .return_value,
            .operand = 0,
        }},
    };

    try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
}

test "ProgramPlan.validate rejects instructions that appear after return_value in a block" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "invalid.return_value_not_final",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 3,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 3,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{
                .kind = .const_i32,
                .dst = 0,
                .operand = 1,
            },
            .{
                .kind = .return_value,
                .operand = 0,
            },
            .{
                .kind = .const_i32,
                .dst = 1,
                .operand = 2,
            },
        },
    };

    try std.testing.expectError(error.InvalidTerminatorInstruction, plan.validate());
}

test "planFromProgram rejects bodyless helper fan-out without explicit bodies" {
    const row = effect_ir.rowFromSpec(.{});
    const root_symbol = effect_ir.SymbolRef{
        .module_path = "examples/fanout.zig",
        .symbol_name = "root",
    };
    const helper_a_symbol = effect_ir.SymbolRef{
        .module_path = "examples/fanout.zig",
        .symbol_name = "helperA",
    };
    const helper_b_symbol = effect_ir.SymbolRef{
        .module_path = "examples/fanout.zig",
        .symbol_name = "helperB",
    };
    const program = effect_ir.Program{
        .functions = &.{
            .{ .symbol = root_symbol, .row = row },
            .{ .symbol = helper_a_symbol, .row = row },
            .{ .symbol = helper_b_symbol, .row = row },
        },
        .call_edges = &.{
            .{ .caller = root_symbol, .callee = helper_a_symbol },
            .{ .caller = root_symbol, .callee = helper_b_symbol },
        },
    };

    const result = comptime internal_program_plan.planFromProgram("example.invalid_bodyless_fanout", program);
    try std.testing.expectError(error.InvalidProgramBodyShape, result);
}

test "planFromProgram rejects bodyless recursive helper graphs without explicit bodies" {
    const row = effect_ir.rowFromSpec(.{});
    const root_symbol = effect_ir.SymbolRef{
        .module_path = "examples/recursive.zig",
        .symbol_name = "root",
    };
    const program = effect_ir.Program{
        .functions = &.{.{ .symbol = root_symbol, .row = row }},
        .call_edges = &.{.{
            .caller = root_symbol,
            .callee = root_symbol,
        }},
    };

    const result = comptime internal_program_plan.planFromProgram("example.invalid_bodyless_cycle", program);
    try std.testing.expectError(error.InvalidProgramBodyShape, result);
}
