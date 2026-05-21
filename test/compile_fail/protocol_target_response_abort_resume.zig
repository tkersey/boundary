// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn plan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 1 },
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
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
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 125,
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
    pub const compiled_plan = plan("protocol-target-response-abort-resume");
};
const Program = boundary.program("protocol-target-response-abort-resume", struct {}, Body);
const Protocol = boundary.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{
        boundary.ir.schema.abort("reject", void),
    },
});
const Reject = Protocol.operation("reject", .{ .Result = i32 });
const Response = Program.Handler.TargetResponse(Reject);

comptime {
    if (!@hasField(Response, "resume")) {
        @compileError("Program.Handler.TargetResponse abort rejects resume");
    }
}
