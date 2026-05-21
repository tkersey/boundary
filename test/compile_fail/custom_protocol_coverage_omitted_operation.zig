// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

const Custom = boundary.ir.schema.Protocol(.{
    .label = "custom",
    .ops = .{
        boundary.ir.schema.transform("step", void, i32),
    },
});
const Rows = Custom.Rows(void, .{
    .requirement_index = 0,
    .first_op = 0,
});

fn plan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const first = boundary.ir.builder.local(root, 0);
    const second = boundary.ir.builder.local(root, 1);
    const Step = Rows.op("step");
    const instructions = [_]boundary.ir.plan.Instruction{
        Step.call(root, first, null) catch unreachable,
        Step.call(root, second, null) catch unreachable,
        boundary.ir.builder.returnValue(root, second) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .first_requirement = 0,
        .requirement_count = 1,
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
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};

    return boundary.ir.builder.finish(.{
        .label = "custom-protocol-coverage-omitted-operation",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = plan();
};
const Program = boundary.program("custom-protocol-coverage-omitted-operation", struct {}, Body);
const First = Program.protocol.operationSite("custom", "step", 0);

comptime {
    Program.protocol.assertOperationSitesCovered(.{First});
}
