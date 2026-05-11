// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const ability = @import("ability");

fn plan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, value, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
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
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "protocol", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "step",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};
    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 122,
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
    pub const compiled_plan = plan("interpreter-elimination-missing-protocol-operation");
};
const Program = ability.program("interpreter-elimination-missing-protocol-operation", struct {}, Body);
const Site = Program.protocol.operationSite("protocol", "step", 0);
const Policy = ability.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{
        ability.ir.schema.transform("check", void, bool),
    },
});
const Check = Policy.operation("check", .{});
const Mapper = struct {
    pub fn @"resume"(_: bool) Program.Handler.SourceOutcome(Site) {
        return Program.Handler.@"resume"(Site, 1);
    }
};
const Handler = struct {
    pub fn handle(_: anytype, _: anytype, _: Program.Handler.Control) Program.Handler.Outcome(Site) {
        return Program.Handler.reinterpret(Site, Check, {}, Mapper);
    }
};
const Morphism = Program.Morphism(.{
    .source = Site,
    .target = Check,
    .Mapper = Mapper,
});
const Interpreter = Program.Interpreter(.{
    Program.Handler.morphism(Morphism, Handler.handle),
});

comptime {
    Interpreter.assertEliminates(Program);
}
