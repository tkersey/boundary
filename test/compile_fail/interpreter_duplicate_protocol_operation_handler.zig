// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const ability = @import("ability");

fn plan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const instructions = [_]ability.ir.plan.Instruction{};
    const functions = [_]ability.ir.plan.Function{.{
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
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};
    return ability.ir.builder.finish(.{
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
const Program = ability.program("interpreter-duplicate-protocol-operation-handler", struct {}, Body);
const Policy = ability.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{
        ability.ir.schema.transform("check", void, bool),
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
