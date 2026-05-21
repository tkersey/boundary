// zlinter-disable declaration_naming require_doc_comment
const boundary = @import("boundary");

const Payload = ?i32;

fn mismatchedVariantPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const instructions = [_]boundary.ir.plan.Instruction{.{
        .kind = .return_value,
        .operand = 0,
    }};
    const value_schemas = [_]boundary.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]boundary.ir.ValueVariantPlan{
        .{ .name = "none" },
        .{ .name = "other", .codec = .i32 },
    };
    const functions = [_]boundary.ir.plan.Function{.{
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
    const locals = [_]boundary.ir.plan.Local{.{ .codec = .sum, .schema_index = 0 }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};

    return boundary.ir.ProgramPlan{
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

const Program = boundary.program("value-schema-variant-mismatch", struct {}, Body);

test "value schema variants must match" {
    _ = Program;
}
