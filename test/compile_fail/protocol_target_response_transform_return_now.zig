// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const ability = @import("ability");

fn plan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 1 },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
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
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};
    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 124,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = plan("protocol-target-response-transform-return-now");
};
const Program = ability.program("protocol-target-response-transform-return-now", struct {}, Body);
const Protocol = ability.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{
        ability.ir.schema.transform("check", void, bool),
    },
});
const Check = Protocol.operation("check", .{});
const Response = Program.Handler.TargetResponse(Check);

comptime {
    if (!@hasField(Response, "return_now")) {
        @compileError("Program.Handler.TargetResponse transform rejects return_now");
    }
}
