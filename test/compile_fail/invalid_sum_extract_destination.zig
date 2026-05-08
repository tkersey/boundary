// zlinter-disable declaration_naming require_doc_comment
const ability = @import("ability");

const Payload = ?i32;

fn invalidSumExtractPlan() ability.ir.ProgramPlan {
    const instructions = [_]ability.ir.plan.Instruction{.{
        .kind = .sum_extract_payload,
        .dst = 1,
        .operand = 0,
        .aux = 1,
    }};
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none" },
        .{ .name = "some", .codec = .i32 },
    };
    const locals = [_]ability.ir.plan.Local{
        .{ .codec = .sum, .schema_index = 0 },
        .{ .codec = .bool },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.ProgramPlan{
        .label = "invalid-sum-extract-destination",
        .ir_hash = 2,
        .entry_index = 0,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_variants = &value_variants,
        .locals = &locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    };
}

const Body = struct {
    pub const value_schema_types = .{Payload};
    pub const compiled_plan = invalidSumExtractPlan();
};

const Program = ability.program("invalid-sum-extract-destination", struct {}, Body);

test "sum extraction destination must match payload" {
    _ = Program;
}
