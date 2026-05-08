// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

fn mustInstruction(result: anyerror!ability.ir.plan.Instruction) ability.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid typed ProgramPlan instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!ability.ir.ProgramPlan) ability.ir.ProgramPlan {
    return result catch |err| std.debug.panic("invalid typed ProgramPlan: {s}", .{@errorName(err)});
}

const EmptyHandlers = struct {};

const Item = struct {
    amount: i32,
};

const Tagged = union(enum) {
    none,
    yes: i32,
};

fn productIdentityPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        mustInstruction(ability.ir.builder.returnValue(root, payload)),
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .product,
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
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Item),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]ability.ir.ValueFieldPlan{.{
        .name = "amount",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return mustPlan(ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 20,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{.{ .codec = .product, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

fn optionalBranchPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const is_some = ability.ir.builder.local(root, 1);
    const result = ability.ir.builder.local(root, 2);
    const instructions = [_]ability.ir.plan.Instruction{
        mustInstruction(ability.ir.builder.sumVariantIs(root, is_some, payload, 1)),
        .{ .kind = .const_i32, .dst = result.index, .operand = 1 },
        mustInstruction(ability.ir.builder.returnValue(root, result)),
        .{ .kind = .const_i32, .dst = result.index, .operand = 0 },
        mustInstruction(ability.ir.builder.returnValue(root, result)),
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(?i32),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "some", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return mustPlan(ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 21,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = &.{
            .{ .codec = .sum, .schema_index = 0 },
            .{ .codec = .bool },
            .{ .codec = .i32 },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

fn taggedPayloadPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const extracted = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        mustInstruction(ability.ir.builder.sumExtractPayload(root, extracted, payload, 1)),
        mustInstruction(ability.ir.builder.returnValue(root, extracted)),
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
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
        .label = @typeName(Tagged),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "yes", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return mustPlan(ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 22,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = &.{
            .{ .codec = .sum, .schema_index = 0 },
            .{ .codec = .i32 },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

fn outputPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 1,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const outputs = [_]ability.ir.plan.Output{.{
        .label = "writer",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = 0,
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return mustPlan(ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 23,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &outputs,
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }));
}

const ProductBody = struct {
    pub const value_schema_types = .{Item};
    pub const compiled_plan = productIdentityPlan("typed-product-example");

    pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Item{ .amount = 42 }}) {
        return .{Item{ .amount = 42 }};
    }
};

const SomeBody = struct {
    pub const value_schema_types = .{?i32};
    pub const compiled_plan = optionalBranchPlan("typed-sum-some-example");

    pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(?i32, 7)}) {
        return .{@as(?i32, 7)};
    }
};

const NoneBody = struct {
    pub const value_schema_types = .{?i32};
    pub const compiled_plan = optionalBranchPlan("typed-sum-none-example");

    pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(?i32, null)}) {
        return .{@as(?i32, null)};
    }
};

const TaggedBody = struct {
    pub const value_schema_types = .{Tagged};
    pub const compiled_plan = taggedPayloadPlan("tagged-payload-example");

    pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Tagged{ .yes = 99 }}) {
        return .{Tagged{ .yes = 99 }};
    }
};

const OutputHandlers = struct {
    writer: struct {
        value: i32,
    },
};

const Cleanup = struct {
    var outputs_deinitialized = false;
};

const OutputBody = struct {
    pub const Outputs = []i32;
    pub const compiled_plan = outputPlan("output-cleanup-example");

    pub fn collectOutputs(allocator: std.mem.Allocator, handlers: *OutputHandlers) !Outputs {
        const outputs = try allocator.alloc(i32, 1);
        outputs[0] = handlers.writer.value;
        return outputs;
    }

    pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
        Cleanup.outputs_deinitialized = true;
        allocator.free(outputs);
    }
};

/// Run typed ProgramPlan examples through the public API.
pub fn run(writer: anytype) !void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const ProductProgram = ability.program("typed-product-example", EmptyHandlers, ProductBody);
    var product = try ProductProgram.run(&runtime, .{});
    defer product.deinit();
    try writer.print("product.amount={d}\n", .{product.value.amount});

    const SomeProgram = ability.program("typed-sum-some-example", EmptyHandlers, SomeBody);
    var some = try SomeProgram.run(&runtime, .{});
    defer some.deinit();
    const NoneProgram = ability.program("typed-sum-none-example", EmptyHandlers, NoneBody);
    var none = try NoneProgram.run(&runtime, .{});
    defer none.deinit();
    try writer.print("optional.some={d} optional.none={d}\n", .{ some.value, none.value });

    const TaggedProgram = ability.program("tagged-payload-example", EmptyHandlers, TaggedBody);
    var tagged = try TaggedProgram.run(&runtime, .{});
    defer tagged.deinit();
    try writer.print("tagged.yes={d}\n", .{tagged.value});

    const OutputProgram = ability.program("output-cleanup-example", OutputHandlers, OutputBody);
    Cleanup.outputs_deinitialized = false;
    var output = try OutputProgram.run(&runtime, .{ .writer = .{ .value = 12 } });
    try writer.print("output.writer={d}\n", .{output.outputs[0]});
    output.deinit();
    try writer.print("output.cleanup={any}\n", .{Cleanup.outputs_deinitialized});

    try writer.print("contract.product_schemas={d} contract.sum_variants={d} contract.output_label={s}\n", .{
        ProductProgram.contract.value_schemas.len,
        SomeProgram.contract.value_variants.len,
        OutputProgram.contract.outputs[0].label,
    });
}

/// Run the typed ProgramPlan example.
pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
