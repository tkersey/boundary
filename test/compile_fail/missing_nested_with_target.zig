// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

const nested_with_metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi";

fn nestedPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .dst = value.index,
            .aux = @intFromEnum(boundary.ir.ValueCodec.i32),
            .string_literal = nested_with_metadata,
        },
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
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
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};

    return boundary.ir.builder.finish(.{
        .label = "missing-nested-with-target",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = nestedPlan();
};

const Program = boundary.program("missing-nested-with-target", struct {}, Body);

test "missing nested-with target fails closed" {
    _ = Program;
}
