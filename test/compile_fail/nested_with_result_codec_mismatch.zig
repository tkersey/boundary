const ability = @import("ability");

const nested_with_metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi";

fn nestedPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const nested = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const nested_value = ability.ir.builder.local(nested, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .dst = root_value.index,
            .aux = @intFromEnum(ability.ir.ValueCodec.string),
            .string_literal = nested_with_metadata,
        },
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = nested_value.index, .operand = 1 },
        ability.ir.builder.returnValue(nested, nested_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .string,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "nested",
            .value_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 2,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = "nested-with-result-codec-mismatch",
        .ir_hash = 3,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = nestedPlan();
    pub const nested_with_targets = .{ability.ir.NestedWithTarget{
        .metadata = nested_with_metadata,
        .function_index = 1,
    }};
};

const Program = ability.program("nested-with-result-codec-mismatch", struct {}, Body);

test "nested-with result codec mismatch is rejected" {
    _ = Program;
}
