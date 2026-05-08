// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const ability = @import("ability");

const nested_with_metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi";

fn nestedPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const intended = ability.ir.builder.function(1);
    const wrong = ability.ir.builder.function(2);
    const root_value = ability.ir.builder.local(root, 0);
    const intended_value = ability.ir.builder.local(intended, 0);
    const wrong_arg = ability.ir.builder.local(wrong, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .dst = root_value.index,
            .aux = @intFromEnum(ability.ir.ValueCodec.i32),
            .string_literal = nested_with_metadata,
        },
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = intended_value.index, .operand = 1 },
        ability.ir.builder.returnValue(intended, intended_value) catch unreachable,
        ability.ir.builder.returnValue(wrong, wrong_arg) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
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
            .symbol_name = "intended",
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
        .{
            .symbol_name = "wrong",
            .value_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 2,
            .local_count = 1,
            .first_block = 2,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 4,
            .instruction_count = 1,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 4, .instruction_count = 1, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = "nested-with-wrong-function-index",
        .ir_hash = 2,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = nestedPlan();
    pub const nested_with_targets = .{ability.ir.NestedWithTarget{
        .metadata = nested_with_metadata,
        .function_index = 2,
    }};
};

const Program = ability.program("nested-with-wrong-function-index", struct {}, Body);

test "wrong nested-with target function index is rejected" {
    _ = Program;
}
