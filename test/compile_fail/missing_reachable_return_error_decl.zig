// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn returnErrorPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const instructions = [_]boundary.ir.plan.Instruction{.{
        .kind = .return_error,
        .string_literal = "Rejected",
    }};
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
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
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};

    return boundary.ir.builder.finish(.{
        .label = "missing-reachable-return-error-decl",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = returnErrorPlan();
};

const Program = boundary.program("missing-reachable-return-error-decl", struct {}, Body);

test "reachable return_error must be declared" {
    _ = Program;
}
