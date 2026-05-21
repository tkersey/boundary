// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn plan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const instructions = [_]boundary.ir.plan.Instruction{};
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .result_codec = .unit,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = 121,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = plan("interpreter-duplicate-protocol-operation-handler");
};
const Program = boundary.program("interpreter-duplicate-protocol-operation-handler", struct {}, Body);
const Policy = boundary.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{
        boundary.ir.schema.transform("check", void, bool),
    },
});
const Check = Policy.operation("check", .{});
const Handler = struct {
    pub fn handle(_: anytype, _: anytype) Program.Handler.TargetResponse(Check) {
        return .{ .@"resume" = true };
    }
};

const Interpreter = Program.Interpreter(.{
    Program.Handler.protocolOperation(Check, Handler.handle),
    Program.Handler.protocolOperation(Check, Handler.handle),
});

comptime {
    _ = Interpreter.coverage();
}
