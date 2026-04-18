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

test "ProgramPlan.validate rejects helper calls whose mismatched callee codec can escape through terminal control" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "invalid.helper_terminal_codec_escape",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{
            .{
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
            },
            .{
                .symbol_name = "helper",
                .value_codec = .string,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 1,
                .local_count = 1,
                .first_block = 1,
                .block_count = 1,
                .first_instruction = 1,
                .instruction_count = 1,
            },
        },
        .requirements = &.{.{
            .label = "guard",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "fail",
            .mode = .abort,
            .payload_codec = .unit,
            .resume_codec = .unit,
        }},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .string },
            .{ .codec = .string },
        },
        .call_args = &.{},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 1,
                .instruction_count = 1,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .return_unit },
            .{ .kind = .return_unit },
        },
        .instructions = &.{
            .{
                .kind = .call_helper,
                .dst = 0,
                .operand = 1,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .call_op,
                .operand = 0,
                .aux = std.math.maxInt(u16),
            },
        },
    };

    try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
}

test "ProgramPlan.validate accepts helper terminal escapes when result codecs match" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "valid.helper_terminal_result_codec_match",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "root",
                .value_codec = .unit,
                .result_codec = .string,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 1,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .string,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 1,
                .block_count = 1,
                .first_instruction = 1,
                .instruction_count = 1,
            },
        },
        .requirements = &.{.{
            .label = "guard",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "fail",
            .mode = .abort,
            .payload_codec = .unit,
            .resume_codec = .unit,
        }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 1,
                .instruction_count = 1,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .return_unit },
            .{ .kind = .return_unit },
        },
        .instructions = &.{
            .{
                .kind = .call_helper,
                .operand = 1,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .call_op,
                .operand = 0,
                .aux = std.math.maxInt(u16),
            },
        },
    };

    try plan.validate();
}

test "ProgramPlan.validate accepts value-returning helpers that abort through a helper call" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "valid.helper_terminal_abort_only_helper",
        .ir_hash = 5,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "root",
                .value_codec = .unit,
                .result_codec = .string,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 1,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .string,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 1,
                .block_count = 1,
                .first_instruction = 1,
                .instruction_count = 1,
            },
            .{
                .symbol_name = "leaf",
                .value_codec = .unit,
                .result_codec = .string,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 2,
                .block_count = 1,
                .first_instruction = 2,
                .instruction_count = 1,
            },
        },
        .requirements = &.{.{
            .label = "guard",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "fail",
            .mode = .abort,
            .payload_codec = .unit,
            .resume_codec = .unit,
        }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 1,
                .instruction_count = 1,
                .terminator_index = 1,
            },
            .{
                .first_instruction = 2,
                .instruction_count = 1,
                .terminator_index = 2,
            },
        },
        .terminators = &.{
            .{ .kind = .return_unit },
            .{ .kind = .return_unit },
            .{ .kind = .return_unit },
        },
        .instructions = &.{
            .{
                .kind = .call_helper,
                .operand = 1,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .call_helper,
                .operand = 2,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .call_op,
                .operand = 0,
                .aux = std.math.maxInt(u16),
            },
        },
    };

    try plan.validate();
}

test "ProgramPlan.validate accepts helper value destinations typed by helper result codecs" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "valid.helper_value_result_codec_match",
        .ir_hash = 2,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "root",
                .value_codec = .string,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 2,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .unit,
                .result_codec = .string,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 1,
                .local_count = 0,
                .first_block = 1,
                .block_count = 1,
                .first_instruction = 2,
                .instruction_count = 1,
            },
        },
        .requirements = &.{.{
            .label = "tooling",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "dispatch",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .unit,
            .has_after = true,
        }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 2,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 2,
                .instruction_count = 1,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .return_value },
            .{ .kind = .return_unit },
        },
        .instructions = &.{
            .{
                .kind = .call_helper,
                .dst = 0,
                .operand = 1,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .return_value,
                .operand = 0,
            },
            .{
                .kind = .call_op,
                .operand = 0,
                .aux = std.math.maxInt(u16),
            },
        },
    };

    try plan.validate();
}

test "ProgramPlan.validate ignores unreachable helper terminal-only paths when checking helper codec escape" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "valid.helper_unreachable_terminal_codec_escape",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{
            .{
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
            },
            .{
                .symbol_name = "helper",
                .value_codec = .string,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 1,
                .local_count = 1,
                .first_block = 1,
                .entry_block = 0,
                .block_count = 2,
                .first_instruction = 1,
                .instruction_count = 3,
            },
        },
        .requirements = &.{.{
            .label = "guard",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "fail",
            .mode = .abort,
            .payload_codec = .unit,
            .resume_codec = .unit,
        }},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .string },
            .{ .codec = .string },
        },
        .call_args = &.{},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 1,
                .instruction_count = 1,
                .terminator_index = 1,
            },
            .{
                .first_instruction = 2,
                .instruction_count = 2,
                .terminator_index = 2,
            },
        },
        .terminators = &.{
            .{ .kind = .return_unit },
            .{ .kind = .return_value },
            .{ .kind = .return_value },
        },
        .instructions = &.{
            .{
                .kind = .call_helper,
                .dst = 0,
                .operand = 1,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .return_value,
                .operand = 0,
            },
            .{
                .kind = .call_op,
                .operand = 0,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .return_value,
                .operand = 0,
            },
        },
    };

    try plan.validate();
}

test "ProgramPlan.validate ignores structurally reachable dead return blocks after abort-only helpers" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "valid.helper_abort_only_dead_return_block",
        .ir_hash = 4,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "root",
                .value_codec = .unit,
                .result_codec = .string,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 1,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .string,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 1,
                .entry_block = 0,
                .block_count = 2,
                .first_instruction = 1,
                .instruction_count = 2,
            },
        },
        .requirements = &.{.{
            .label = "guard",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "fail",
            .mode = .abort,
            .payload_codec = .unit,
            .resume_codec = .unit,
        }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 1,
                .instruction_count = 1,
                .terminator_index = 1,
            },
            .{
                .first_instruction = 2,
                .instruction_count = 1,
                .terminator_index = 2,
            },
        },
        .terminators = &.{
            .{ .kind = .return_unit },
            .{ .kind = .jump, .primary = 2 },
            .{ .kind = .return_value },
        },
        .instructions = &.{
            .{
                .kind = .call_helper,
                .operand = 1,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .call_op,
                .operand = 0,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .return_value,
                .operand = 0,
            },
        },
    };

    try plan.validate();
}

test "ProgramPlan.validate rejects mixed terminal and value helpers without a valid destination local" {
    const plan = internal_program_plan.ProgramPlan{
        .label = "invalid.helper_mixed_terminal_and_value_result_local",
        .ir_hash = 3,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "root",
                .value_codec = .unit,
                .result_codec = .string,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 1,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .string,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 1,
                .block_count = 1,
                .first_instruction = 1,
                .instruction_count = 2,
            },
        },
        .requirements = &.{.{
            .label = "picker",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "pick",
            .mode = .choice,
            .payload_codec = .unit,
            .resume_codec = .string,
        }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 1,
                .instruction_count = 2,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .return_unit },
            .{ .kind = .return_value },
        },
        .instructions = &.{
            .{
                .kind = .call_helper,
                .dst = 0,
                .operand = 1,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .call_op,
                .dst = 0,
                .operand = 0,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .return_value,
                .operand = 0,
            },
        },
    };

    try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
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

test "planFromProgram rejects explicit helper bodies whose local prefix disagrees with declared parameters" {
    const row = effect_ir.rowFromSpec(.{});
    const root_symbol = effect_ir.SymbolRef{
        .module_path = "examples/mismatched_helper.zig",
        .symbol_name = "root",
    };
    const helper_symbol = effect_ir.SymbolRef{
        .module_path = "examples/mismatched_helper.zig",
        .symbol_name = "helper",
    };
    const program = effect_ir.Program{
        .functions = &.{
            .{
                .symbol = root_symbol,
                .row = row,
            },
            .{
                .symbol = helper_symbol,
                .row = row,
                .parameter_codecs = &.{.bool},
            },
        },
        .call_edges = &.{.{
            .caller = root_symbol,
            .callee = helper_symbol,
        }},
        .function_bodies = &.{
            .{
                .local_codecs = &.{.i32},
                .call_arg_locals = &.{0},
                .entry_block = 0,
                .blocks = &.{.{
                    .instructions = &.{.{
                        .kind = .call_helper,
                        .operand = 1,
                        .aux = 0,
                    }},
                    .terminator = .{ .kind = .return_unit },
                }},
            },
            .{
                .local_codecs = &.{.i32},
                .entry_block = 0,
                .blocks = &.{.{
                    .instructions = &.{},
                    .terminator = .{ .kind = .return_unit },
                }},
            },
        },
    };

    const result = comptime internal_program_plan.planFromProgram("example.invalid_explicit_param_prefix", program);
    try std.testing.expectError(error.InvalidProgramBodyShape, result);
}
