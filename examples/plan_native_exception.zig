// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

fn mustInstruction(result: anyerror!boundary.ir.plan.Instruction) boundary.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid exception instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!boundary.ir.ProgramPlan) boundary.ir.ProgramPlan {
    return result catch |err| std.debug.panic("invalid exception plan: {s}", .{@errorName(err)});
}

const ProductPayload = struct {
    amount: i32,
};

const OptionalPayload = ?i32;

fn scalarExceptionPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = payload.index, .operand = 40 },
        mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), payload)),
    };
    const ExceptionRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("exception", boundary.effect.exception.Schema(i32, error{}, void), void),
        .{ .requirement_index = 0, .first_op = 0 },
    );
    const requirements = [_]boundary.ir.plan.Requirement{ExceptionRows.requirement};
    const ops = ExceptionRows.ops;
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .result_codec = .i32,
        .first_requirement = 0,
        .requirement_count = 1,
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
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};

    return mustPlan(boundary.ir.builder.finish(.{
        .label = "plan-native-exception-scalar",
        .ir_hash = 70,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

fn productExceptionPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), payload)),
    };
    const ExceptionRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("exception", boundary.effect.exception.Schema(ProductPayload, error{}, void), void),
        .{
            .requirement_index = 0,
            .first_op = 0,
            .schema_refs = boundary.ir.schema.SchemaRefs(.{
                boundary.ir.schema.ref(ProductPayload, 0),
            }),
        },
    );
    const requirements = [_]boundary.ir.plan.Requirement{ExceptionRows.requirement};
    const ops = ExceptionRows.ops;
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .result_codec = .product,
        .result_schema_index = 0,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
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
    const schemas = [_]boundary.ir.ValueSchemaPlan{.{
        .label = @typeName(ProductPayload),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const fields = [_]boundary.ir.ValueFieldPlan{.{
        .name = "amount",
        .codec = .i32,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};

    return mustPlan(boundary.ir.builder.finish(.{
        .label = "plan-native-exception-product",
        .ir_hash = 71,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &schemas,
        .value_fields = &fields,
        .value_variants = &.{},
        .locals = &.{.{ .codec = .product, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

fn sumExceptionPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), payload)),
    };
    const ExceptionRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("exception", boundary.effect.exception.Schema(OptionalPayload, error{}, void), void),
        .{
            .requirement_index = 0,
            .first_op = 0,
            .schema_refs = boundary.ir.schema.SchemaRefs(.{
                boundary.ir.schema.ref(OptionalPayload, 0),
            }),
        },
    );
    const requirements = [_]boundary.ir.plan.Requirement{ExceptionRows.requirement};
    const ops = ExceptionRows.ops;
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .result_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
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
    const variants = [_]boundary.ir.ValueVariantPlan{
        boundary.ir.value.unitVariant("none"),
        boundary.ir.value.variant("some", i32),
    };
    const schemas = [_]boundary.ir.ValueSchemaPlan{.{
        .label = @typeName(OptionalPayload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = @intCast(variants.len),
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};

    return mustPlan(boundary.ir.builder.finish(.{
        .label = "plan-native-exception-sum",
        .ir_hash = 72,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &schemas,
        .value_fields = &.{},
        .value_variants = &variants,
        .locals = &.{.{ .codec = .sum, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

const ScalarHandlers = struct {
    throw: struct {
        pub fn dispatch(_: *const @This(), payload: i32) !i32 {
            return payload + 1;
        }
    },
};

const ProductHandlers = struct {
    throw: struct {
        pub fn dispatch(_: *const @This(), payload: ProductPayload) !ProductPayload {
            return .{ .amount = payload.amount + 1 };
        }
    },
};

const SumHandlers = struct {
    throw: struct {
        pub fn dispatch(_: *const @This(), payload: OptionalPayload) !i32 {
            return (payload orelse 0) + 1;
        }
    },
};

const ScalarBody = struct {
    pub const compiled_plan = scalarExceptionPlan();
};

const ProductBody = struct {
    pub const value_schema_types = .{ProductPayload};
    pub const compiled_plan = productExceptionPlan();

    pub fn encodeArgs(_: ProductHandlers) @TypeOf(.{ProductPayload{ .amount = 50 }}) {
        return .{ProductPayload{ .amount = 50 }};
    }
};

const SumBody = struct {
    pub const value_schema_types = .{OptionalPayload};
    pub const compiled_plan = sumExceptionPlan();

    pub fn encodeArgs(_: SumHandlers) @TypeOf(.{@as(OptionalPayload, 60)}) {
        return .{@as(OptionalPayload, 60)};
    }
};

pub fn run(writer: anytype) !void {
    var runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const ScalarProgram = boundary.program("plan-native-exception-scalar", ScalarHandlers, ScalarBody);
    const ProductProgram = boundary.program("plan-native-exception-product", ProductHandlers, ProductBody);
    const SumProgram = boundary.program("plan-native-exception-sum", SumHandlers, SumBody);

    var scalar = try ScalarProgram.run(&runtime, .{ .throw = .{} });
    defer scalar.deinit();
    var product = try ProductProgram.run(&runtime, .{ .throw = .{} });
    defer product.deinit();
    var sum = try SumProgram.run(&runtime, .{ .throw = .{} });
    defer sum.deinit();

    try writer.print("scalar={d} product={d} sum={d}\n", .{ scalar.value, product.value.amount, sum.value });
    try writer.print("contract.op={s} mode={s} payload={s} lifecycle={s}\n", .{
        ScalarProgram.contract.ops[0].op_name,
        @tagName(ScalarProgram.contract.ops[0].mode),
        @tagName(ProductProgram.contract.ops[0].payload_ref.codec),
        @tagName(ScalarProgram.contract.requirements[0].lifecycle_tag),
    });
}

/// Run the plan-native exception example.
pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
