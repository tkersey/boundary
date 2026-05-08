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

const ProductBody = struct {
    pub const value_schema_types = .{Item};
    pub const compiled_plan = ability.ir.builder.typed.productIdentity(
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
    pub const compiled_plan = ability.ir.builder.typed.sumVariantI32Branch(
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
    pub const compiled_plan = ability.ir.builder.typed.sumVariantI32Branch(
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
    pub const compiled_plan = ability.ir.builder.typed.sumExtractI32Payload(
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
    pub const compiled_plan = ability.ir.builder.typed.unitWithOutputs(
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
