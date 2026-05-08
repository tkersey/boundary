const ability = @import("ability");

const Payload = ?i32;

fn mismatchedVariantPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const instructions = [_]ability.ir.plan.Instruction{.{
        .kind = .return_value,
        .operand = 0,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none" },
        .{ .name = "other", .codec = .i32 },
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .sum,
        .value_schema_index = 0,
        .parameter_count = 1,
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
    const locals = [_]ability.ir.plan.Local{.{ .codec = .sum, .schema_index = 0 }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.ProgramPlan{
        .label = "value-schema-variant-mismatch",
        .ir_hash = 1,
        .entry_index = root.index,
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
    pub const compiled_plan = mismatchedVariantPlan();

    pub fn encodeArgs(_: struct {}) @TypeOf(.{@as(Payload, 1)}) {
        return .{@as(Payload, 1)};
    }
};

const Program = ability.program("value-schema-variant-mismatch", struct {}, Body);

test "value schema variants must match" {
    _ = Program;
}
