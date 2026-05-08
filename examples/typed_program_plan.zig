// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const EmptyHandlers = struct {};

const Item = struct {
    amount: i32,
};

const Tagged = union(enum) {
    none,
    yes: i32,
};

const item_fields = [_]ability.ir.ValueFieldPlan{
    ability.ir.value.field("amount", i32),
};

const optional_variants = [_]ability.ir.ValueVariantPlan{
    ability.ir.value.unitVariant("none"),
    ability.ir.value.variant("some", i32),
};

const tagged_variants = [_]ability.ir.ValueVariantPlan{
    ability.ir.value.unitVariant("none"),
    ability.ir.value.variant("yes", i32),
};

const writer_outputs = [_]ability.ir.plan.Output{.{
    .label = "writer",
    .codec = .i32,
}};

fn mustInstruction(result: anyerror!ability.ir.plan.Instruction) ability.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid typed ProgramPlan example instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!ability.ir.ProgramPlan) ability.ir.ProgramPlan {
    return result catch |err| std.debug.panic("invalid typed ProgramPlan example plan: {s}", .{@errorName(err)});
}

fn constI32(dst: ability.ir.builder.LocalRef, comptime literal: i32) ability.ir.plan.Instruction {
    if (literal >= 0 and literal <= std.math.maxInt(u16)) {
        return .{ .kind = .const_i32, .dst = dst.index, .operand = @intCast(literal) };
    }
    return .{
        .kind = .const_i32,
        .dst = dst.index,
        .string_literal = std.fmt.comptimePrint("{d}", .{literal}),
    };
}

fn productIdentityPlan(
    comptime Payload: type,
    comptime label: []const u8,
    comptime fields: []const ability.ir.ValueFieldPlan,
) ability.ir.ProgramPlan {
    const root = comptime ability.ir.builder.function(0);
    const payload = comptime ability.ir.builder.local(root, 0);
    const schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .product,
        .first_field = 0,
        .field_count = @intCast(fields.len),
    }};

    return mustPlan(ability.ir.builder.layout.finish(.{
        .label = label,
        .ir_hash = 0x746270000002,
        .entry = root,
        .value_schemas = &schemas,
        .value_fields = fields,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = ability.ir.ValueRef{ .codec = .product, .schema_index = 0 },
            .parameter_count = 1,
            .locals = .{
                .{ .codec = .product, .schema_index = 0 },
            },
            .blocks = .{.{
                .instructions = .{
                    mustInstruction(ability.ir.builder.returnValue(root, payload)),
                },
                .terminator = ability.ir.plan.Terminator{ .kind = .return_value },
            }},
        }},
    }));
}

const SumVariantI32BranchSpec = struct {
    label: []const u8,
    variants: []const ability.ir.ValueVariantPlan,
    variant_ordinal: u16,
    matched_value: i32,
    fallback_value: i32,
};

fn sumVariantI32BranchPlan(
    comptime Sum: type,
    comptime spec: SumVariantI32BranchSpec,
) ability.ir.ProgramPlan {
    const root = comptime ability.ir.builder.function(0);
    const payload = comptime ability.ir.builder.local(root, 0);
    const condition = comptime ability.ir.builder.local(root, 1);
    const result = comptime ability.ir.builder.local(root, 2);
    const schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Sum),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = @intCast(spec.variants.len),
    }};

    return mustPlan(ability.ir.builder.layout.finish(.{
        .label = spec.label,
        .ir_hash = 0x746270000003,
        .entry = root,
        .value_schemas = &schemas,
        .value_variants = spec.variants,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = ability.ir.ValueRef{ .codec = .i32 },
            .parameter_count = 1,
            .locals = .{
                .{ .codec = .sum, .schema_index = 0 },
                .{ .codec = .bool },
                .{ .codec = .i32 },
            },
            .blocks = .{
                .{
                    .instructions = .{
                        mustInstruction(ability.ir.builder.sumVariantIs(root, condition, payload, spec.variant_ordinal)),
                    },
                    .terminator = ability.ir.plan.Terminator{ .kind = .branch_if, .primary = 1, .secondary = 2 },
                },
                .{
                    .instructions = .{
                        constI32(result, spec.matched_value),
                        mustInstruction(ability.ir.builder.returnValue(root, result)),
                    },
                    .terminator = ability.ir.plan.Terminator{ .kind = .return_value },
                },
                .{
                    .instructions = .{
                        constI32(result, spec.fallback_value),
                        mustInstruction(ability.ir.builder.returnValue(root, result)),
                    },
                    .terminator = ability.ir.plan.Terminator{ .kind = .return_value },
                },
            },
        }},
    }));
}

fn sumExtractI32PayloadPlan(
    comptime Sum: type,
    comptime label: []const u8,
    comptime variants: []const ability.ir.ValueVariantPlan,
    comptime variant_ordinal: u16,
) ability.ir.ProgramPlan {
    const root = comptime ability.ir.builder.function(0);
    const payload = comptime ability.ir.builder.local(root, 0);
    const extracted = comptime ability.ir.builder.local(root, 1);
    const schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Sum),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = @intCast(variants.len),
    }};

    return mustPlan(ability.ir.builder.layout.finish(.{
        .label = label,
        .ir_hash = 0x746270000004,
        .entry = root,
        .value_schemas = &schemas,
        .value_variants = variants,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = ability.ir.ValueRef{ .codec = .i32 },
            .parameter_count = 1,
            .locals = .{
                .{ .codec = .sum, .schema_index = 0 },
                .{ .codec = .i32 },
            },
            .blocks = .{.{
                .instructions = .{
                    mustInstruction(ability.ir.builder.sumExtractPayload(root, extracted, payload, variant_ordinal)),
                    mustInstruction(ability.ir.builder.returnValue(root, extracted)),
                },
                .terminator = ability.ir.plan.Terminator{ .kind = .return_value },
            }},
        }},
    }));
}

fn unitWithOutputsPlan(
    comptime label: []const u8,
    comptime outputs: []const ability.ir.plan.Output,
) ability.ir.ProgramPlan {
    const root = comptime ability.ir.builder.function(0);

    return mustPlan(ability.ir.builder.layout.finish(.{
        .label = label,
        .ir_hash = 0x746270000005,
        .entry = root,
        .outputs = outputs,
        .functions = .{.{
            .symbol_name = "run",
            .outputs = ability.ir.builder.layout.span(0, outputs.len),
            .locals = .{},
            .blocks = .{.{
                .instructions = .{},
                .terminator = ability.ir.plan.Terminator{ .kind = .return_unit },
            }},
        }},
    }));
}

const ProductBody = struct {
    pub const value_schema_types = .{Item};
    pub const compiled_plan = productIdentityPlan(
        Item,
        "typed-product-example",
        &item_fields,
    );

    pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Item{ .amount = 42 }}) {
        return .{Item{ .amount = 42 }};
    }
};

const SomeBody = struct {
    pub const value_schema_types = .{?i32};
    pub const compiled_plan = sumVariantI32BranchPlan(
        ?i32,
        .{
            .label = "typed-sum-some-example",
            .variants = &optional_variants,
            .variant_ordinal = 1,
            .matched_value = 1,
            .fallback_value = 0,
        },
    );

    pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(?i32, 7)}) {
        return .{@as(?i32, 7)};
    }
};

const NoneBody = struct {
    pub const value_schema_types = .{?i32};
    pub const compiled_plan = sumVariantI32BranchPlan(
        ?i32,
        .{
            .label = "typed-sum-none-example",
            .variants = &optional_variants,
            .variant_ordinal = 1,
            .matched_value = 1,
            .fallback_value = 0,
        },
    );

    pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(?i32, null)}) {
        return .{@as(?i32, null)};
    }
};

const TaggedBody = struct {
    pub const value_schema_types = .{Tagged};
    pub const compiled_plan = sumExtractI32PayloadPlan(
        Tagged,
        "tagged-payload-example",
        &tagged_variants,
        1,
    );

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
    pub const compiled_plan = unitWithOutputsPlan(
        "output-cleanup-example",
        &writer_outputs,
    );

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
