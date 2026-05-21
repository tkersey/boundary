// zlinter-disable declaration_naming require_doc_comment no_empty_block no_inferred_error_unions no_swallow_error
const boundary = @import("boundary");
const std = @import("std");

fn outputPlan() boundary.ir.ProgramPlan {
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 0,
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
    const outputs = [_]boundary.ir.plan.Output{.{ .label = "writer", .codec = .i32 }};
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};

    return boundary.ir.builder.finish(.{
        .label = "invalid-output-cleanup-hook",
        .ir_hash = 5,
        .entry = boundary.ir.builder.function(0),
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &outputs,
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch unreachable;
}

const Body = struct {
    pub const Outputs = []const i32;
    pub const compiled_plan = outputPlan();

    pub fn collectOutputs(_: std.mem.Allocator, _: *struct {}) !Outputs {
        return &.{};
    }

    pub fn deinitOutputs(_: std.mem.Allocator, _: i32) void {}
};

const Program = boundary.program("invalid-output-cleanup-hook", struct {}, Body);

test "output cleanup hook must match outputs" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var result = try Program.run(&runtime, .{});
    result.deinit();
}
