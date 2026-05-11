// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const ability = @import("ability");
const std = @import("std");

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
        .ir_hash = 129,
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
    pub const compiled_plan = plan("interpreter-protocol-handler-mutable-payload");
};
const Program = ability.program("interpreter-protocol-handler-mutable-payload", struct {}, Body);
const Site = Program.protocol.operationSite("protocol", "step", 0);
const Policy = ability.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{
        ability.ir.schema.transform("check", [][]const u8, bool),
    },
});
const Check = Policy.operation("check", .{});
const Mapper = struct {
    pub fn @"resume"(_: bool) Program.Handler.SourceOutcome(Site) {
        return Program.Handler.@"resume"(Site, 1);
    }
};
const Morphism = Program.Morphism(.{ .source = Site, .target = Check, .Mapper = Mapper });
const Host = struct {
    items: [2][]const u8 = .{ "left", "right" },
};

const SourceHandler = struct {
    pub fn handle(host: *Host, request: anytype, _: Program.Handler.Control) !Program.Handler.MorphismOutcome(Morphism) {
        _ = try request.payload();
        return Program.Handler.reinterpret(Morphism, host.items[0..]);
    }
};

const MutatingPolicyHandler = struct {
    pub fn handle(_: *Host, request: anytype) !Program.Handler.TargetResponse(Check) {
        var payload = try request.payload();
        payload[0] = "changed";
        return .forward;
    }
};

const Interpreter = Program.Interpreter(.{
    Program.Handler.morphism(Morphism, SourceHandler.handle),
    Program.Handler.protocolOperation(Check, MutatingPolicyHandler.handle),
});

test "protocol handler cannot mutate request payload storage" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var host = Host{};
    _ = try Interpreter.run(&runtime, .{}, &host, .{});
}
