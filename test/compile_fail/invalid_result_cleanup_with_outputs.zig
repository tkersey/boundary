const ability = @import("ability");
const std = @import("std");

fn outputPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const functions = [_]ability.ir.plan.Function{.{
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

    return ability.ir.builder.finish(.{
        .label = "invalid-result-cleanup-with-outputs",
        .ir_hash = 2,
        .entry = root,
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
        return &[_]i32{};
    }

    pub fn deinitResult(_: std.mem.Allocator, _: void, _: Outputs) void {}
};

const Program = ability.program("invalid-result-cleanup-with-outputs", struct {}, Body);

test "result cleanup must not own outputs" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var result = try Program.run(&runtime, .{});
    result.deinit();
}
