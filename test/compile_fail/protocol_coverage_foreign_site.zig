// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn plan(comptime label: []const u8, comptime hash: u64) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, value, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.returnValue(root, value) catch unreachable,
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
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{ .label = "protocol", .first_op = 0, .op_count = 1 }};
    const ops = [_]boundary.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "step",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};

    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = hash,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = plan("protocol-coverage-foreign", 4);
};
const ForeignBody = struct {
    pub const compiled_plan = plan("protocol-coverage-foreign", 4);
};
const Handlers = struct {};
const Program = boundary.program("protocol-coverage-foreign", Handlers, Body);
const ForeignProgram = boundary.program("protocol-coverage-foreign", Handlers, ForeignBody);
const ForeignSite = ForeignProgram.protocol.operationSite("protocol", "step", 0);

comptime {
    Program.protocol.assertOperationSitesCovered(.{ForeignSite});
}
