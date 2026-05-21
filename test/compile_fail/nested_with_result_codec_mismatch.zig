// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

const nested_with_metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi";

fn nestedPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const nested = boundary.ir.builder.function(1);
    const root_value = boundary.ir.builder.local(root, 0);
    const nested_value = boundary.ir.builder.local(nested, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .dst = root_value.index,
            .aux = @intFromEnum(boundary.ir.ValueCodec.string),
            .string_literal = nested_with_metadata,
        },
        boundary.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = nested_value.index, .operand = 1 },
        boundary.ir.builder.returnValue(nested, nested_value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{
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
    const blocks = [_]boundary.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]boundary.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return boundary.ir.builder.finish(.{
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
    pub const nested_with_targets = .{boundary.ir.NestedWithTarget{
        .metadata = nested_with_metadata,
        .function_index = 1,
    }};
};

const Program = boundary.program("nested-with-result-codec-mismatch", struct {}, Body);

test "nested-with result codec mismatch is rejected" {
    _ = Program;
}
