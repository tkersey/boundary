// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn plan(comptime label: []const u8) boundary.ir.ProgramPlan {
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
        .ir_hash = 0x7070726e01,
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

fn handlerPlan(comptime label: []const u8) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 1 },
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 0,
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
        .ir_hash = 0x7070726e02,
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

const SourceBody = struct {
    pub const compiled_plan = plan("provider-program-transform-return-now");
};
const SourceProgram = boundary.program("provider-program-transform-return-now", struct {}, SourceBody);
const Site = SourceProgram.protocol.operationSite("protocol", "step", 0);

const HandlerBody = struct {
    pub const compiled_plan = handlerPlan("provider-program-transform-return-now-handler");
};
const HandlerProgram = boundary.program("provider-program-transform-return-now-handler", struct {}, HandlerBody);

const Decl = SourceProgram.Exchange.ProviderHandler.program(.{
    .label = "bad-provider-program-result",
    .op = Site,
    .program = HandlerProgram,
    .map_request = .unit_args,
    .map_result = .result_to_return_now,
});

comptime {
    _ = Decl.provider_program_mapping_fingerprint;
}
