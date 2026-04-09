const artifact = @import("shift_shared").artifact;
const host = @import("host_adapter_v1.zig");
const lowered_machine = @import("shift_shared").lowered_machine_internal;
const program_plan = @import("shift_shared").internal_program_plan;
const std = @import("std");

/// Result of executing ArtifactV1 bytes through the synchronous HostAdapterV1 runtime.
pub const ExecutionResultV1 = struct {
    value: lowered_machine.ProgramValue,
    logs: []host.HostLogEntryV1,

    /// Release the owned runtime value and captured host logs.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        deinitProgramValue(allocator, &self.value);
        for (self.logs) |*entry| entry.deinit(allocator);
        allocator.free(self.logs);
        self.* = .{
            .value = .none,
            .logs = &.{},
        };
    }
};

/// Decode ArtifactV1 bytes, execute the entry function, and capture the host-effect transcript.
pub fn runArtifact(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    adapter: host.HostAdapterV1,
) anyerror!ExecutionResultV1 {
    var decoded = try artifact.decode(allocator, bytes);
    defer decoded.deinit(allocator);
    const plan = try decoded.toProgramPlan(allocator);
    defer deepFreeProgramPlan(allocator, plan);
    var value_arena = std.heap.ArenaAllocator.init(allocator);
    defer value_arena.deinit();

    var logs = std.ArrayList(host.HostLogEntryV1).empty;
    errdefer {
        for (logs.items) |*entry| entry.deinit(allocator);
        logs.deinit(allocator);
    }

    var next_request_id: u64 = 1;
    var execution: ExecutionContext = .{
        .allocator = allocator,
        .value_allocator = value_arena.allocator(),
        .decoded = &decoded,
        .plan = plan,
        .adapter = adapter,
        .logs = &logs,
        .next_request_id = &next_request_id,
    };
    const result = try executeFunction(
        &execution,
        plan.entry_index,
        &.{},
    );
    const owned_value = try cloneProgramValue(allocator, switch (result) {
        .terminal => |value| value,
        .value => |value| value,
    });
    return .{
        .value = owned_value,
        .logs = try logs.toOwnedSlice(allocator),
    };
}

const FunctionResult = union(enum) {
    terminal: lowered_machine.ProgramValue,
    value: lowered_machine.ProgramValue,
};

const ExecutionContext = struct {
    allocator: std.mem.Allocator,
    value_allocator: std.mem.Allocator,
    decoded: *const artifact.ArtifactV1,
    plan: program_plan.ProgramPlan,
    adapter: host.HostAdapterV1,
    logs: *std.ArrayList(host.HostLogEntryV1),
    next_request_id: *u64,
};

fn executeFunction(
    ctx: *ExecutionContext,
    function_index: u16,
    args: []const lowered_machine.ProgramValue,
) anyerror!FunctionResult {
    const function = ctx.plan.functions[function_index];
    var locals = try ctx.allocator.alloc(lowered_machine.ProgramValue, function.local_count);
    defer ctx.allocator.free(locals);
    @memset(locals, .none);
    if (args.len != function.parameter_count) return error.ProgramContractViolation;
    for (args, 0..) |arg, index| locals[index] = arg;

    var current_block_index = function.first_block + function.entry_block;
    var instruction_index = ctx.plan.blocks[current_block_index].first_instruction;
    var return_local: ?u16 = null;

    while (true) {
        const block = ctx.plan.blocks[current_block_index];
        const instruction_end = block.first_instruction + block.instruction_count;
        while (instruction_index < instruction_end) : (instruction_index += 1) {
            const instruction = ctx.plan.instructions[instruction_index];
            switch (instruction.kind) {
                .add_const_i32 => locals[instruction.dst] = switch (locals[instruction.operand]) {
                    .i32 => |typed| .{ .i32 = typed + @as(i32, @intCast(instruction.aux)) },
                    else => return error.ProgramContractViolation,
                },
                .call_helper => {
                    const callee = ctx.plan.functions[instruction.operand];
                    const helper_args = try ctx.allocator.alloc(lowered_machine.ProgramValue, callee.parameter_count);
                    defer ctx.allocator.free(helper_args);
                    for (helper_args, 0..) |*slot, arg_index| {
                        const local_id = ctx.plan.call_args[instruction.aux + arg_index];
                        slot.* = locals[local_id];
                    }
                    const helper_result = try executeFunction(ctx, instruction.operand, helper_args);
                    switch (helper_result) {
                        .value => |value| {
                            if (callee.value_codec != .unit) locals[instruction.dst] = value;
                        },
                        .terminal => |value| return .{ .terminal = value },
                    }
                },
                .call_op => {
                    const op = ctx.plan.ops[instruction.operand];
                    const payload = if (op.payload_codec == .unit) .none else locals[instruction.aux];
                    const op_result = try callHostOp(ctx, instruction.operand, payload);
                    switch (op_result) {
                        .resumed => |value| {
                            if (op.resume_codec != .unit) locals[instruction.dst] = value;
                        },
                        .terminal => |value| return .{ .terminal = value },
                    }
                },
                .compare_eq_zero => locals[instruction.dst] = switch (locals[instruction.operand]) {
                    .i32 => |typed| .{ .bool = typed == 0 },
                    .usize => |typed| .{ .bool = typed == 0 },
                    else => return error.ProgramContractViolation,
                },
                .const_i32 => locals[instruction.dst] = .{ .i32 = decodeI32InstructionLiteral(instruction) },
                .const_string => locals[instruction.dst] = .{ .string = instruction.string_literal },
                .return_value => return_local = instruction.operand,
                .sub_one => locals[instruction.dst] = switch (locals[instruction.operand]) {
                    .i32 => |typed| .{ .i32 = typed - 1 },
                    .usize => |typed| .{ .usize = typed - 1 },
                    else => return error.ProgramContractViolation,
                },
            }
        }

        const terminator = ctx.plan.terminators[block.terminator_index];
        switch (terminator.kind) {
            .branch_if => {
                const predicate_instruction = ctx.plan.instructions[instruction_end - 1];
                const predicate = switch (locals[predicate_instruction.dst]) {
                    .bool => |typed| typed,
                    else => return error.ProgramContractViolation,
                };
                current_block_index = if (predicate) terminator.primary else terminator.secondary;
                instruction_index = ctx.plan.blocks[current_block_index].first_instruction;
                return_local = null;
            },
            .jump => {
                current_block_index = terminator.primary;
                instruction_index = ctx.plan.blocks[current_block_index].first_instruction;
                return_local = null;
            },
            .return_unit => return .{ .value = .none },
            .return_value => return .{ .value = locals[return_local orelse return error.ProgramContractViolation] },
        }
    }
}

const OpDispatchResult = union(enum) {
    resumed: lowered_machine.ProgramValue,
    terminal: lowered_machine.ProgramValue,
};

fn callHostOp(
    ctx: *ExecutionContext,
    op_index: u16,
    payload: lowered_machine.ProgramValue,
) anyerror!OpDispatchResult {
    const op = ctx.plan.ops[op_index];
    const resolved = resolveCapabilityOp(ctx.decoded.capabilities, ctx.decoded.requirement_capability_ids, ctx.plan, op_index) orelse return error.ProgramContractViolation;
    var request = host.HostEffectRequestV1{
        .request_id = ctx.next_request_id.*,
        .capability_id = resolved.capability.capability_id,
        .op_id = resolved.capability_op.op_id,
        .body = .{ .tool_call = .{
            .tool_id = try ctx.allocator.dupe(u8, resolved.capability.label),
            .call_id = ctx.next_request_id.*,
            .op_name = try ctx.allocator.dupe(u8, op.op_name),
            .arguments = try programValueToDataValue(ctx.allocator, op.payload_codec, payload),
        } },
    };
    ctx.next_request_id.* += 1;
    defer request.deinit(ctx.allocator);

    var response = try ctx.adapter.dispatch(ctx.allocator, request);
    defer response.deinit(ctx.allocator);
    if (response.request_id != request.request_id) return error.ProgramContractViolation;

    try ctx.logs.append(ctx.allocator, .{
        .request = try request.clone(ctx.allocator),
        .result = try response.clone(ctx.allocator),
    });

    return switch (response.body) {
        .success => |tool_result| switch (tool_result.control) {
            .@"resume" => .{ .resumed = try dataValueToProgramValue(ctx.value_allocator, op.resume_codec, tool_result.value) },
            .return_now, .abort => .{ .terminal = try dataValueToProgramValue(ctx.value_allocator, functionValueCodecForOp(ctx.plan, op_index), tool_result.value) },
        },
        .rejected, .failed => error.ProgramContractViolation,
    };
}

const ResolvedCapabilityOp = struct {
    capability: artifact.CapabilityV1,
    capability_op: artifact.CapabilityOpV1,
};

fn resolveCapabilityOp(
    capabilities: []const artifact.CapabilityV1,
    requirement_capability_ids: []const u16,
    plan: program_plan.ProgramPlan,
    op_index: u16,
) ?ResolvedCapabilityOp {
    if (op_index >= plan.ops.len) return null;
    const op = plan.ops[op_index];
    if (op.requirement_index >= requirement_capability_ids.len or op.requirement_index >= plan.requirements.len) return null;
    const requirement = plan.requirements[op.requirement_index];
    if (op_index < requirement.first_op) return null;
    const capability = findCapabilityById(capabilities, requirement_capability_ids[op.requirement_index]) orelse return null;
    const capability_op_index = op_index - requirement.first_op;
    if (capability_op_index >= capability.ops.len) return null;
    return .{
        .capability = capability,
        .capability_op = capability.ops[capability_op_index],
    };
}

fn findCapabilityById(capabilities: []const artifact.CapabilityV1, capability_id: u16) ?artifact.CapabilityV1 {
    for (capabilities) |capability| {
        if (capability.capability_id == capability_id) return capability;
    }
    return null;
}

fn functionValueCodecForOp(plan: program_plan.ProgramPlan, op_index: u16) program_plan.ValueCodec {
    for (plan.functions) |function| {
        const req_start: usize = function.first_requirement;
        const req_end = req_start + function.requirement_count;
        for (plan.requirements[req_start..req_end]) |requirement| {
            const op_start = requirement.first_op;
            const op_end = op_start + requirement.op_count;
            if (op_index >= op_start and op_index < op_end) return function.value_codec;
        }
    }
    return .unit;
}

fn programValueToDataValue(
    allocator: std.mem.Allocator,
    codec: program_plan.ValueCodec,
    value: lowered_machine.ProgramValue,
) !host.DataValueV1 {
    return switch (codec) {
        .unit => .null,
        .bool => switch (value) {
            .bool => |typed| .{ .bool = typed },
            else => error.ProgramContractViolation,
        },
        .i32 => switch (value) {
            .i32 => |typed| .{ .i64 = typed },
            else => error.ProgramContractViolation,
        },
        .string => switch (value) {
            .string => |typed| .{ .string = try allocator.dupe(u8, typed) },
            else => error.ProgramContractViolation,
        },
        .usize => switch (value) {
            .usize => |typed| .{ .i64 = @intCast(typed) },
            else => error.ProgramContractViolation,
        },
        .string_list => error.ProgramContractViolation,
    };
}

fn dataValueToProgramValue(
    allocator: std.mem.Allocator,
    codec: program_plan.ValueCodec,
    value: host.DataValueV1,
) !lowered_machine.ProgramValue {
    return switch (codec) {
        .unit => .none,
        .bool => switch (value) {
            .bool => |typed| .{ .bool = typed },
            else => error.ProgramContractViolation,
        },
        .i32 => switch (value) {
            .i64 => |typed| .{ .i32 = @intCast(typed) },
            else => error.ProgramContractViolation,
        },
        .string => switch (value) {
            .string => |typed| .{ .string = try allocator.dupe(u8, typed) },
            else => error.ProgramContractViolation,
        },
        .usize => switch (value) {
            .i64 => |typed| .{ .usize = @intCast(typed) },
            else => error.ProgramContractViolation,
        },
        .string_list => error.ProgramContractViolation,
    };
}

fn decodeI32InstructionLiteral(instruction: program_plan.Instruction) i32 {
    const low = @as(u32, instruction.operand);
    const high = @as(u32, instruction.aux) << 16;
    return @bitCast(high | low);
}

fn deepFreeProgramPlan(allocator: std.mem.Allocator, plan: program_plan.ProgramPlan) void {
    allocator.free(plan.label);
    for (plan.functions) |item| allocator.free(item.symbol_name);
    allocator.free(@constCast(plan.functions));
    for (plan.requirements) |item| allocator.free(item.label);
    allocator.free(@constCast(plan.requirements));
    for (plan.ops) |item| allocator.free(item.op_name);
    allocator.free(@constCast(plan.ops));
    for (plan.outputs) |item| allocator.free(item.label);
    allocator.free(@constCast(plan.outputs));
    allocator.free(@constCast(plan.locals));
    allocator.free(@constCast(plan.call_args));
    allocator.free(@constCast(plan.blocks));
    allocator.free(@constCast(plan.terminators));
    for (plan.instructions) |item| allocator.free(item.string_literal);
    allocator.free(@constCast(plan.instructions));
}

fn cloneProgramValue(allocator: std.mem.Allocator, value: lowered_machine.ProgramValue) !lowered_machine.ProgramValue {
    return switch (value) {
        .none => .none,
        .bool => |typed| .{ .bool = typed },
        .i32 => |typed| .{ .i32 = typed },
        .usize => |typed| .{ .usize = typed },
        .string => |typed| .{ .string = try allocator.dupe(u8, typed) },
    };
}

fn deinitProgramValue(allocator: std.mem.Allocator, value: *lowered_machine.ProgramValue) void {
    switch (value.*) {
        .string => |typed| allocator.free(typed),
        else => {},
    }
    value.* = .none;
}
