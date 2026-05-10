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

const ProductSchemas = ability.ir.schema.Registry(.{Item});
const OptionalSchemas = ability.ir.schema.Registry(.{?i32});
const TaggedSchemas = ability.ir.schema.Registry(.{Tagged});

const writer_outputs = [_]ability.ir.plan.Output{.{
    .label = "writer",
    .codec = .i32,
}};

fn productIdentityPlan(
    comptime Payload: type,
    comptime label: []const u8,
    comptime Schemas: type,
) ability.ir.ProgramPlan {
    const semantic = ability.ir.builder.semantic;
    return (semantic.finish(.{
        .label = label,
        .ir_hash = 0x746270000002,
        .entry = "run",
        .schemas = Schemas,
        .functions = .{.{
            .symbol_name = "run",
            .params = .{
                semantic.param("payload", Payload),
            },
            .locals = .{},
            .result = Payload,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{},
                .terminator = semantic.returnValue("payload"),
            }},
        }},
    }) catch |err| @compileError("invalid semantic product ProgramPlan example: " ++ @errorName(err))).plan;
}

const SumVariantI32BranchSpec = struct {
    label: []const u8,
    variant_ordinal: u16,
    matched_value: i32,
    fallback_value: i32,
};

fn sumVariantI32BranchPlan(
    comptime Sum: type,
    comptime Schemas: type,
    comptime spec: SumVariantI32BranchSpec,
) ability.ir.ProgramPlan {
    const semantic = ability.ir.builder.semantic;
    return (semantic.finish(.{
        .label = spec.label,
        .ir_hash = 0x746270000003,
        .entry = "run",
        .schemas = Schemas,
        .functions = .{.{
            .symbol_name = "run",
            .params = .{
                semantic.param("payload", Sum),
            },
            .locals = .{
                semantic.local("condition", bool),
                semantic.local("result", i32),
            },
            .result = i32,
            .blocks = .{
                .{
                    .name = "entry",
                    .instructions = .{
                        semantic.sumVariantIs("condition", "payload", spec.variant_ordinal),
                    },
                    .terminator = semantic.branchIf("condition", .{ .then = "matched", .@"else" = "fallback" }),
                },
                .{
                    .name = "matched",
                    .instructions = .{
                        semantic.constI32("result", spec.matched_value),
                    },
                    .terminator = semantic.returnValue("result"),
                },
                .{
                    .name = "fallback",
                    .instructions = .{
                        semantic.constI32("result", spec.fallback_value),
                    },
                    .terminator = semantic.returnValue("result"),
                },
            },
        }},
    }) catch |err| @compileError("invalid semantic sum branch ProgramPlan example: " ++ @errorName(err))).plan;
}

fn sumExtractI32PayloadPlan(
    comptime Sum: type,
    comptime label: []const u8,
    comptime Schemas: type,
    comptime variant_ordinal: u16,
) ability.ir.ProgramPlan {
    const semantic = ability.ir.builder.semantic;
    return (semantic.finish(.{
        .label = label,
        .ir_hash = 0x746270000004,
        .entry = "run",
        .schemas = Schemas,
        .functions = .{.{
            .symbol_name = "run",
            .params = .{
                semantic.param("payload", Sum),
            },
            .locals = .{
                semantic.local("extracted", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    semantic.sumExtractPayload("extracted", "payload", variant_ordinal),
                },
                .terminator = semantic.returnValue("extracted"),
            }},
        }},
    }) catch |err| @compileError("invalid semantic sum extract ProgramPlan example: " ++ @errorName(err))).plan;
}

fn unitWithOutputsPlan(
    comptime label: []const u8,
    comptime outputs: []const ability.ir.plan.Output,
) ability.ir.ProgramPlan {
    const semantic = ability.ir.builder.semantic;
    return (semantic.finish(.{
        .label = label,
        .ir_hash = 0x746270000005,
        .entry = "run",
        .outputs = outputs,
        .functions = .{.{
            .symbol_name = "run",
            .params = .{},
            .locals = .{},
            .outputs = semantic.span(0, outputs.len),
            .blocks = .{.{
                .name = "entry",
                .instructions = .{},
                .terminator = semantic.returnUnit(),
            }},
        }},
    }) catch |err| @compileError("invalid semantic output ProgramPlan example: " ++ @errorName(err))).plan;
}

const ProductBody = struct {
    pub const value_schema_types = ProductSchemas.value_schema_types;
    pub const compiled_plan = productIdentityPlan(
        Item,
        "typed-product-example",
        ProductSchemas,
    );

    pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Item{ .amount = 42 }}) {
        return .{Item{ .amount = 42 }};
    }
};

const SomeBody = struct {
    pub const value_schema_types = OptionalSchemas.value_schema_types;
    pub const compiled_plan = sumVariantI32BranchPlan(
        ?i32,
        OptionalSchemas,
        .{
            .label = "typed-sum-some-example",
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
    pub const value_schema_types = OptionalSchemas.value_schema_types;
    pub const compiled_plan = sumVariantI32BranchPlan(
        ?i32,
        OptionalSchemas,
        .{
            .label = "typed-sum-none-example",
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
    pub const value_schema_types = TaggedSchemas.value_schema_types;
    pub const compiled_plan = sumExtractI32PayloadPlan(
        Tagged,
        "tagged-payload-example",
        TaggedSchemas,
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
