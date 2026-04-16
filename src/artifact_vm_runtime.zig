const artifact = @import("artifact_api");
const host = @import("host_adapter_v1");
const lowered_machine = @import("lowered_machine");
const program_plan = @import("internal_program_plan");
const std = @import("std");

const capability_global_tool_call = "tool.call";
const capability_global_tool_after = "tool.after";

/// Result of executing ArtifactV1 bytes through the synchronous HostAdapterV1 runtime.
pub const ExecutionOutputV1 = struct {
    label: []u8,
    codec: host.OutputCodecV1,
    value: host.DataValueV1,

    /// Release the owned output label and value payload.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.label);
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

/// Result of executing ArtifactV1 bytes through the synchronous HostAdapterV1 runtime.
pub const ExecutionResultV1 = struct {
    value: lowered_machine.ProgramValue,
    outputs: []ExecutionOutputV1,
    logs: []host.HostLogEntryV1,

    /// Release the owned runtime value, captured outputs, and host logs.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        deinitProgramValue(allocator, &self.value);
        deinitExecutionOutputs(allocator, self.outputs);
        for (self.logs) |*entry| entry.deinit(allocator);
        allocator.free(self.logs);
        self.* = .{
            .value = .none,
            .outputs = &.{},
            .logs = &.{},
        };
    }
};

/// Typed host failure returned by the ArtifactV1 runtime with the captured host transcript.
pub const HostFailureResultV1 = struct {
    failure: host.FailureV1,
    logs: []host.HostLogEntryV1,

    /// Release the owned host failure payload and captured host logs.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.failure.deinit(allocator);
        for (self.logs) |*entry| entry.deinit(allocator);
        allocator.free(self.logs);
        self.* = undefined;
    }
};

/// Result of executing ArtifactV1 bytes through the synchronous HostAdapterV1 runtime.
pub const RunArtifactResultV1 = union(enum) {
    completed: ExecutionResultV1,
    failed: HostFailureResultV1,
    rejected: HostFailureResultV1,

    /// Release the owned execution or host-failure result.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .completed => |*result| result.deinit(allocator),
            .rejected => |*failure| failure.deinit(allocator),
            .failed => |*failure| failure.deinit(allocator),
        }
        self.* = undefined;
    }
};

/// Decode ArtifactV1 bytes, execute the entry function, and capture the host-effect transcript.
pub fn runArtifact(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    adapter: host.HostAdapterV1,
) anyerror!RunArtifactResultV1 {
    var decoded = try artifact.decode(allocator, bytes);
    defer decoded.deinit(allocator);
    const plan = try decoded.toProgramPlan(allocator);
    defer deepFreeProgramPlan(allocator, plan);

    var logs = std.ArrayList(host.HostLogEntryV1).empty;
    errdefer {
        for (logs.items) |*entry| entry.deinit(allocator);
        logs.deinit(allocator);
    }

    var next_request_id: u64 = 1;
    var execution: ExecutionContext = .{
        .allocator = allocator,
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
    return switch (result) {
        .terminal => |value| try completeExecutionResult(allocator, &execution, &logs, value),
        .value => |value| try completeExecutionResult(allocator, &execution, &logs, value),
        .rejected => |failure| blk: {
            errdefer {
                var owned_failure = failure;
                owned_failure.deinit(allocator);
            }
            break :blk .{
                .rejected = .{
                    .failure = failure,
                    .logs = try logs.toOwnedSlice(allocator),
                },
            };
        },
        .failed => |failure| blk: {
            errdefer {
                var owned_failure = failure;
                owned_failure.deinit(allocator);
            }
            break :blk .{
                .failed = .{
                    .failure = failure,
                    .logs = try logs.toOwnedSlice(allocator),
                },
            };
        },
    };
}

fn completeExecutionResult(
    allocator: std.mem.Allocator,
    ctx: *ExecutionContext,
    logs: *std.ArrayList(host.HostLogEntryV1),
    runtime_value: RuntimeValue,
) anyerror!RunArtifactResultV1 {
    var owned_runtime_value = runtime_value;
    defer deinitRuntimeValue(allocator, &owned_runtime_value);
    const output_result = try materializeExecutionOutputs(ctx);
    const outputs = switch (output_result) {
        .outputs => |outputs| outputs,
        .failed => |failure| {
            errdefer {
                var owned_failure = failure;
                owned_failure.deinit(allocator);
            }
            return .{
                .failed = .{
                    .failure = failure,
                    .logs = try logs.toOwnedSlice(allocator),
                },
            };
        },
    };
    errdefer deinitExecutionOutputs(allocator, outputs);

    var owned_value = try materializeExecutionValue(allocator, &owned_runtime_value);
    errdefer deinitProgramValue(allocator, &owned_value);
    return .{
        .completed = .{
            .value = owned_value,
            .outputs = outputs,
            .logs = try logs.toOwnedSlice(allocator),
        },
    };
}

const RuntimeValue = struct {
    value: lowered_machine.ProgramValue,
    owned: bool = false,
};

const OutputMaterializationResult = union(enum) {
    failed: host.FailureV1,
    outputs: []ExecutionOutputV1,
};

const FunctionResult = union(enum) {
    failed: host.FailureV1,
    rejected: host.FailureV1,
    terminal: RuntimeValue,
    value: RuntimeValue,
};

const AfterFrame = struct {
    op_index: u16,
    call_id: u64,
};

const ExecutionContext = struct {
    allocator: std.mem.Allocator,
    decoded: *const artifact.ArtifactV1,
    plan: program_plan.ProgramPlan,
    adapter: host.HostAdapterV1,
    logs: *std.ArrayList(host.HostLogEntryV1),
    next_request_id: *u64,
};

fn entryOutputs(plan: program_plan.ProgramPlan) []const program_plan.OutputPlan {
    const entry_function = plan.functions[plan.entry_index];
    return plan.outputs[entry_function.first_output .. entry_function.first_output + entry_function.output_count];
}

fn outputCodecFromPlanCodec(codec: program_plan.ValueCodec) host.OutputCodecV1 {
    return switch (codec) {
        .unit => .unit,
        .bool => .bool,
        .i32 => .i32,
        .string => .string,
        .string_list => .string_list,
        .usize => .usize,
    };
}

fn dataValueMatchesOutputCodec(codec: host.OutputCodecV1, value: host.DataValueV1) bool {
    return switch (codec) {
        .unit => value == .null,
        .bool => value == .bool,
        .i32 => switch (value) {
            .i64 => |typed| std.math.cast(i32, typed) != null,
            else => false,
        },
        .string => value == .string,
        .string_list => switch (value) {
            .array => |items| blk: {
                for (items) |item| if (item != .string) break :blk false;
                break :blk true;
            },
            else => false,
        },
        .usize => switch (value) {
            .u64 => |typed| std.math.cast(usize, typed) != null,
            .i64 => |typed| std.math.cast(usize, typed) != null,
            else => false,
        },
    };
}

fn deinitExecutionOutputs(allocator: std.mem.Allocator, outputs: []ExecutionOutputV1) void {
    for (outputs) |*output| output.deinit(allocator);
    allocator.free(outputs);
}

fn deinitExecutionOutputsPrefix(allocator: std.mem.Allocator, outputs: []ExecutionOutputV1, initialized: usize) void {
    for (outputs[0..initialized]) |*output| output.deinit(allocator);
    allocator.free(outputs);
}

fn deinitCollectedOutputValues(allocator: std.mem.Allocator, values: []host.DataValueV1) void {
    for (values) |*value| value.deinit(allocator);
    allocator.free(values);
}

fn providerFailureFailure(allocator: std.mem.Allocator, message: []const u8) !host.FailureV1 {
    return .{
        .code = try allocator.dupe(u8, "provider_failure"),
        .message = try allocator.dupe(u8, message),
        .owns_code = true,
        .owns_message = true,
    };
}

fn materializeExecutionOutputs(ctx: *ExecutionContext) anyerror!OutputMaterializationResult {
    const declared = entryOutputs(ctx.plan);
    if (declared.len == 0) return .{ .outputs = try ctx.allocator.alloc(ExecutionOutputV1, 0) };

    const descriptors = try ctx.allocator.alloc(host.OutputDescriptorV1, declared.len);
    defer ctx.allocator.free(descriptors);
    for (declared, descriptors) |output, *descriptor| {
        descriptor.* = .{
            .label = output.label,
            .codec = outputCodecFromPlanCodec(output.codec),
        };
    }

    var values = ctx.adapter.collectOutputs(ctx.allocator, descriptors) catch |err| switch (err) {
        error.MissingOutputSnapshot => {
            return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host adapter must collect declared outputs") };
        },
        else => return .{ .failed = try providerFailureFailure(ctx.allocator, @errorName(err)) },
    };
    errdefer deinitCollectedOutputValues(ctx.allocator, values);
    if (values.len != declared.len) {
        return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host output snapshot count must match the declared outputs") };
    }

    const outputs = try ctx.allocator.alloc(ExecutionOutputV1, declared.len);
    var initialized: usize = 0;
    errdefer deinitExecutionOutputsPrefix(ctx.allocator, outputs, initialized);
    for (declared, values, 0..) |declared_output, value, index| {
        const codec = outputCodecFromPlanCodec(declared_output.codec);
        if (!dataValueMatchesOutputCodec(codec, value)) {
            return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host output snapshot value does not match the declared codec") };
        }
        outputs[index] = .{
            .label = try ctx.allocator.dupe(u8, declared_output.label),
            .codec = codec,
            .value = value,
        };
        values[index] = .null;
        initialized += 1;
    }
    ctx.allocator.free(values);
    return .{ .outputs = outputs };
}

fn executeFunction(
    ctx: *ExecutionContext,
    function_index: u16,
    args: []const lowered_machine.ProgramValue,
) anyerror!FunctionResult {
    const function = ctx.plan.functions[function_index];
    const function_result_codec = program_plan.functionResultCodec(function);
    var locals = try ctx.allocator.alloc(lowered_machine.ProgramValue, function.local_count);
    defer ctx.allocator.free(locals);
    const local_owns_value = try ctx.allocator.alloc(bool, function.local_count);
    defer ctx.allocator.free(local_owns_value);
    @memset(locals, .none);
    @memset(local_owns_value, false);
    defer releaseLocals(ctx.allocator, locals, local_owns_value);
    if (args.len != function.parameter_count) return error.ProgramContractViolation;
    for (args, 0..) |arg, index| {
        switch (arg) {
            .string => |typed| {
                locals[index] = .{ .string = try ctx.allocator.dupe(u8, typed) };
                local_owns_value[index] = true;
            },
            else => locals[index] = arg,
        }
    }

    var current_block_index = function.first_block + function.entry_block;
    var instruction_index = ctx.plan.blocks[current_block_index].first_instruction;
    var return_local: ?u16 = null;
    var after_stack = std.ArrayList(AfterFrame).empty;
    defer after_stack.deinit(ctx.allocator);

    while (true) {
        const block = ctx.plan.blocks[current_block_index];
        const instruction_end = block.first_instruction + block.instruction_count;
        while (instruction_index < instruction_end) : (instruction_index += 1) {
            const instruction = ctx.plan.instructions[instruction_index];
            switch (instruction.kind) {
                .add_i32 => setLocal(
                    ctx.allocator,
                    locals,
                    local_owns_value,
                    instruction.dst,
                    .{
                        .value = switch (locals[instruction.operand]) {
                            .i32 => |left| switch (locals[instruction.aux]) {
                                .i32 => |right| .{ .i32 = std.math.add(i32, left, right) catch return error.ProgramContractViolation },
                                else => return error.ProgramContractViolation,
                            },
                            else => return error.ProgramContractViolation,
                        },
                    },
                ),
                .add_const_i32 => setLocal(
                    ctx.allocator,
                    locals,
                    local_owns_value,
                    instruction.dst,
                    .{
                        .value = switch (locals[instruction.operand]) {
                            .i32 => |typed| .{ .i32 = std.math.add(i32, typed, @as(i32, @intCast(instruction.aux))) catch return error.ProgramContractViolation },
                            else => return error.ProgramContractViolation,
                        },
                    },
                ),
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
                            if (callee.value_codec != .unit) setLocal(ctx.allocator, locals, local_owns_value, instruction.dst, value);
                        },
                        .terminal => |value| return try unwindAfterStack(ctx, function.value_codec, function_result_codec, &after_stack, .{ .terminal = value }),
                        .rejected => |failure| return .{ .rejected = failure },
                        .failed => |failure| return .{ .failed = failure },
                    }
                },
                .call_op => {
                    const op = ctx.plan.ops[instruction.operand];
                    const payload = if (op.payload_codec == .unit) .none else locals[instruction.aux];
                    const op_result = try callHostOp(ctx, instruction.operand, payload);
                    switch (op_result) {
                        .resumed => |resumed| {
                            if (op.resume_codec != .unit) setLocal(ctx.allocator, locals, local_owns_value, instruction.dst, resumed.value);
                            if (hasAfterCapabilityOp(ctx.decoded.capabilities, ctx.decoded.requirement_capability_ids, ctx.plan, instruction.operand)) {
                                try after_stack.append(ctx.allocator, .{
                                    .op_index = instruction.operand,
                                    .call_id = resumed.call_id,
                                });
                            }
                        },
                        .terminal => |value| return try unwindAfterStack(ctx, function.value_codec, function_result_codec, &after_stack, .{ .terminal = value }),
                        .rejected => |failure| return .{ .rejected = failure },
                        .failed => |failure| return .{ .failed = failure },
                    }
                },
                .compare_eq_zero => setLocal(
                    ctx.allocator,
                    locals,
                    local_owns_value,
                    instruction.dst,
                    .{
                        .value = switch (locals[instruction.operand]) {
                            .i32 => |typed| .{ .bool = typed == 0 },
                            .usize => |typed| .{ .bool = typed == 0 },
                            else => return error.ProgramContractViolation,
                        },
                    },
                ),
                .const_i32 => setLocal(
                    ctx.allocator,
                    locals,
                    local_owns_value,
                    instruction.dst,
                    .{
                        .value = switch (functionLocalCodec(ctx.plan, function, instruction.dst) orelse return error.ProgramContractViolation) {
                            .i32 => .{ .i32 = decodeI32InstructionLiteral(instruction) },
                            .usize => .{ .usize = decodeU32InstructionLiteral(instruction) },
                            else => return error.ProgramContractViolation,
                        },
                    },
                ),
                .const_usize => setLocal(
                    ctx.allocator,
                    locals,
                    local_owns_value,
                    instruction.dst,
                    .{
                        .value = .{
                            .usize = std.fmt.parseUnsigned(usize, instruction.string_literal, 0) catch
                                return error.ProgramContractViolation,
                        },
                    },
                ),
                .const_string => setLocal(ctx.allocator, locals, local_owns_value, instruction.dst, .{ .value = .{ .string = instruction.string_literal } }),
                .return_value => return_local = instruction.operand,
                .sub_one => setLocal(
                    ctx.allocator,
                    locals,
                    local_owns_value,
                    instruction.dst,
                    .{
                        .value = switch (locals[instruction.operand]) {
                            .i32 => |typed| .{ .i32 = std.math.sub(i32, typed, 1) catch return error.ProgramContractViolation },
                            .usize => |typed| .{ .usize = std.math.sub(usize, typed, 1) catch return error.ProgramContractViolation },
                            else => return error.ProgramContractViolation,
                        },
                    },
                ),
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
            .return_unit => return try unwindAfterStack(ctx, function.value_codec, function_result_codec, &after_stack, .{ .value = .{ .value = .none } }),
            .return_value => return try unwindAfterStack(
                ctx,
                function.value_codec,
                function_result_codec,
                &after_stack,
                .{ .value = takeLocalValue(locals, local_owns_value, return_local orelse return error.ProgramContractViolation) },
            ),
        }
    }
}

const ResumedOp = struct {
    value: RuntimeValue,
    call_id: u64,
};

const OpDispatchResult = union(enum) {
    failed: host.FailureV1,
    rejected: host.FailureV1,
    resumed: ResumedOp,
    terminal: RuntimeValue,
};

fn hostControlMatchesOpMode(mode: program_plan.ControlMode, control: host.ToolControlV1) bool {
    return switch (mode) {
        .transform => control == .@"resume",
        .choice => switch (control) {
            .@"resume", .return_now => true,
            .abort => false,
        },
        .abort => switch (control) {
            .return_now, .abort => true,
            .@"resume" => false,
        },
    };
}

fn callHostOp(
    ctx: *ExecutionContext,
    op_index: u16,
    payload: lowered_machine.ProgramValue,
) anyerror!OpDispatchResult {
    const op = ctx.plan.ops[op_index];
    const resolved = resolveCapabilityOp(ctx.decoded.capabilities, ctx.decoded.requirement_capability_ids, ctx.plan, op_index) orelse return error.ProgramContractViolation;
    var request: host.HostEffectRequestV1 = blk: {
        const tool_id = try ctx.allocator.dupe(u8, resolved.capability.label);
        errdefer ctx.allocator.free(tool_id);
        const op_name = try ctx.allocator.dupe(u8, op.op_name);
        errdefer ctx.allocator.free(op_name);
        const arguments = try programValueToDataValue(ctx.allocator, op.payload_codec, payload);
        errdefer {
            var owned_arguments = arguments;
            owned_arguments.deinit(ctx.allocator);
        }
        break :blk .{
            .request_id = ctx.next_request_id.*,
            .capability_id = resolved.capability.capability_id,
            .op_id = resolved.capability_op.op_id,
            .body = .{ .tool_call = .{
                .tool_id = tool_id,
                .call_id = ctx.next_request_id.*,
                .op_name = op_name,
                .arguments = arguments,
                .owns_tool_id = true,
                .owns_op_name = true,
                .arguments_ownership = .deep,
            } },
        };
    };
    ctx.next_request_id.* += 1;
    defer request.deinit(ctx.allocator);

    var response: host.HostEffectResultV1 = ctx.adapter.dispatch(ctx.allocator, request) catch |err|
        try providerFailureResult(ctx.allocator, request.request_id, @errorName(err));
    defer response.deinit(ctx.allocator);

    var log_entry: host.HostLogEntryV1 = blk: {
        var request_clone = try request.clone(ctx.allocator);
        errdefer request_clone.deinit(ctx.allocator);
        var response_clone = try response.clone(ctx.allocator);
        errdefer response_clone.deinit(ctx.allocator);
        break :blk .{
            .request = request_clone,
            .result = response_clone,
        };
    };
    var logged = false;
    errdefer if (!logged) log_entry.deinit(ctx.allocator);
    try ctx.logs.append(ctx.allocator, log_entry);
    logged = true;

    if (response.schema_version != 1) return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply schema_version must be 1") };
    if (response.request_id != request.request_id) return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply request_id must echo the request") };
    switch (response.body) {
        .success => |tool_result| {
            const tool_call = request.body.tool_call;
            if (!std.mem.eql(u8, tool_result.tool_id, tool_call.tool_id)) {
                return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply tool_id must echo the request") };
            }
            if (tool_result.call_id != tool_call.call_id) {
                return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply call_id must echo the request") };
            }
        },
        else => {},
    }

    return switch (response.body) {
        .success => |tool_result| blk: {
            if (!hostControlMatchesOpMode(op.mode, tool_result.control)) {
                return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply control is incompatible with the op mode") };
            }
            break :blk switch (tool_result.control) {
                .@"resume" => .{
                    .resumed = .{
                        .value = dataValueToRuntimeValue(ctx.allocator, op.resume_codec, tool_result.value) catch |err| switch (err) {
                            error.ProgramContractViolation => {
                                return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply value does not match the declared codec") };
                            },
                            else => return err,
                        },
                        .call_id = request.body.tool_call.call_id,
                    },
                },
                .return_now, .abort => .{
                    .terminal = dataValueToRuntimeValue(
                        ctx.allocator,
                        artifact.terminalResultCodecForOp(ctx.plan, op_index) catch return error.ProgramContractViolation,
                        tool_result.value,
                    ) catch |err| switch (err) {
                        error.ProgramContractViolation => {
                            return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply value does not match the declared codec") };
                        },
                        else => return err,
                    },
                },
            };
        },
        .rejected => |failure| .{ .rejected = try failure.clone(ctx.allocator) },
        .failed => |failure| .{ .failed = try failure.clone(ctx.allocator) },
    };
}

fn providerFailureResult(
    allocator: std.mem.Allocator,
    request_id: u64,
    message: []const u8,
) !host.HostEffectResultV1 {
    return .{
        .request_id = request_id,
        .body = .{ .failed = .{
            .code = try allocator.dupe(u8, "provider_failure"),
            .message = try allocator.dupe(u8, message),
            .owns_code = true,
            .owns_message = true,
        } },
    };
}

fn invalidHostReplyFailure(
    allocator: std.mem.Allocator,
    message: []const u8,
) !host.FailureV1 {
    return .{
        .code = try allocator.dupe(u8, "invalid_host_reply"),
        .message = try allocator.dupe(u8, message),
        .owns_code = true,
        .owns_message = true,
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
    const capability_op = findCapabilityOpByPlanOrdinalAndGlobalName(
        capability.ops,
        op_index - requirement.first_op,
        capability_global_tool_call,
    ) orelse return null;
    return .{
        .capability = capability,
        .capability_op = capability_op,
    };
}

fn resolveAfterCapabilityOp(
    capabilities: []const artifact.CapabilityV1,
    requirement_capability_ids: []const u16,
    plan: program_plan.ProgramPlan,
    op_index: u16,
) ?ResolvedCapabilityOp {
    if (op_index >= plan.ops.len) return null;
    const op = plan.ops[op_index];
    if (op.mode == .abort) return null;
    if (op.requirement_index >= requirement_capability_ids.len or op.requirement_index >= plan.requirements.len) return null;
    const requirement = plan.requirements[op.requirement_index];
    if (op_index < requirement.first_op) return null;
    const capability = findCapabilityById(capabilities, requirement_capability_ids[op.requirement_index]) orelse return null;
    const capability_op = findCapabilityOpByPlanOrdinalAndGlobalName(
        capability.ops,
        op_index - requirement.first_op,
        capability_global_tool_after,
    ) orelse return null;
    return .{
        .capability = capability,
        .capability_op = capability_op,
    };
}

fn findCapabilityById(capabilities: []const artifact.CapabilityV1, capability_id: u16) ?artifact.CapabilityV1 {
    for (capabilities) |capability| {
        if (capability.capability_id == capability_id) return capability;
    }
    return null;
}

fn findCapabilityOpByPlanOrdinalAndGlobalName(
    ops: []const artifact.CapabilityOpV1,
    plan_op_ordinal: u16,
    global_op_name: []const u8,
) ?artifact.CapabilityOpV1 {
    for (ops) |op| {
        if (op.plan_op_ordinal == plan_op_ordinal and std.mem.eql(u8, op.global_op_name, global_op_name)) return op;
    }
    return null;
}

fn hasAfterCapabilityOp(
    capabilities: []const artifact.CapabilityV1,
    requirement_capability_ids: []const u16,
    plan: program_plan.ProgramPlan,
    op_index: u16,
) bool {
    return resolveAfterCapabilityOp(capabilities, requirement_capability_ids, plan, op_index) != null;
}

fn afterMethodNameAlloc(allocator: std.mem.Allocator, op_name: []const u8) ![]u8 {
    var buffer = std.ArrayList(u8).empty;
    errdefer buffer.deinit(allocator);
    try buffer.appendSlice(allocator, "after");
    var capitalize_next = true;
    for (op_name) |byte| {
        if (byte == '_') {
            try buffer.append(allocator, byte);
            capitalize_next = true;
            continue;
        }
        if (capitalize_next and byte >= 'a' and byte <= 'z') {
            try buffer.append(allocator, byte - ('a' - 'A'));
        } else {
            try buffer.append(allocator, byte);
        }
        capitalize_next = false;
    }
    return buffer.toOwnedSlice(allocator);
}

fn unwindAfterStack(
    ctx: *ExecutionContext,
    function_value_codec: program_plan.ValueCodec,
    function_result_codec: program_plan.ValueCodec,
    after_stack: *std.ArrayList(AfterFrame),
    result: FunctionResult,
) anyerror!FunctionResult {
    var final_result = result;
    while (after_stack.items.len != 0) {
        const after_frame = after_stack.pop().?;
        final_result = switch (final_result) {
            .value => |value| blk: {
                var current = value;
                switch (try callHostAfterOp(ctx, function_value_codec, function_result_codec, after_frame.op_index, after_frame.call_id, current)) {
                    .value => |next| {
                        deinitRuntimeValue(ctx.allocator, &current);
                        break :blk .{ .value = next };
                    },
                    .failed => |failure| {
                        deinitRuntimeValue(ctx.allocator, &current);
                        break :blk .{ .failed = failure };
                    },
                    .rejected => |failure| {
                        deinitRuntimeValue(ctx.allocator, &current);
                        break :blk .{ .rejected = failure };
                    },
                    .terminal => unreachable,
                }
            },
            .terminal => |value| .{ .terminal = value },
            .failed, .rejected => final_result,
        };
        switch (final_result) {
            .failed, .rejected => break,
            else => {},
        }
    }
    return final_result;
}

// zlinter-disable max_positional_args - the artifact after-hook bridge keeps value/result codec seams explicit to preserve direct-interpreter parity.
fn callHostAfterOp(
    ctx: *ExecutionContext,
    function_value_codec: program_plan.ValueCodec,
    function_result_codec: program_plan.ValueCodec,
    op_index: u16,
    call_id: u64,
    answer: RuntimeValue,
) anyerror!FunctionResult {
    const resolved = resolveAfterCapabilityOp(ctx.decoded.capabilities, ctx.decoded.requirement_capability_ids, ctx.plan, op_index) orelse return error.ProgramContractViolation;
    const op = ctx.plan.ops[op_index];
    const op_name = try afterMethodNameAlloc(ctx.allocator, op.op_name);
    defer ctx.allocator.free(op_name);
    var request: host.HostEffectRequestV1 = blk: {
        const tool_id = try ctx.allocator.dupe(u8, resolved.capability.label);
        errdefer ctx.allocator.free(tool_id);
        const request_op_name = try ctx.allocator.dupe(u8, op_name);
        errdefer ctx.allocator.free(request_op_name);
        const arguments = try programValueToDataValue(ctx.allocator, function_value_codec, answer.value);
        errdefer {
            var owned_arguments = arguments;
            owned_arguments.deinit(ctx.allocator);
        }
        break :blk .{
            .request_id = ctx.next_request_id.*,
            .capability_id = resolved.capability.capability_id,
            .op_id = resolved.capability_op.op_id,
            .body = .{ .tool_call = .{
                .tool_id = tool_id,
                .call_id = call_id,
                .op_name = request_op_name,
                .arguments = arguments,
                .owns_tool_id = true,
                .owns_op_name = true,
                .arguments_ownership = .deep,
            } },
        };
    };
    ctx.next_request_id.* += 1;
    defer request.deinit(ctx.allocator);

    var response: host.HostEffectResultV1 = ctx.adapter.dispatch(ctx.allocator, request) catch |err|
        try providerFailureResult(ctx.allocator, request.request_id, @errorName(err));
    defer response.deinit(ctx.allocator);

    var log_entry: host.HostLogEntryV1 = blk: {
        var request_clone = try request.clone(ctx.allocator);
        errdefer request_clone.deinit(ctx.allocator);
        var response_clone = try response.clone(ctx.allocator);
        errdefer response_clone.deinit(ctx.allocator);
        break :blk .{
            .request = request_clone,
            .result = response_clone,
        };
    };
    var logged = false;
    errdefer if (!logged) log_entry.deinit(ctx.allocator);
    try ctx.logs.append(ctx.allocator, log_entry);
    logged = true;

    if (response.schema_version != 1) return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply schema_version must be 1") };
    if (response.request_id != request.request_id) return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply request_id must echo the request") };
    switch (response.body) {
        .success => |tool_result| {
            const tool_call = request.body.tool_call;
            if (!std.mem.eql(u8, tool_result.tool_id, tool_call.tool_id)) {
                return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply tool_id must echo the request") };
            }
            if (tool_result.call_id != tool_call.call_id) {
                return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply call_id must echo the request") };
            }
            if (tool_result.control != .@"resume") {
                return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply control is incompatible with the op mode") };
            }
            return .{
                .value = dataValueToRuntimeValue(ctx.allocator, function_result_codec, tool_result.value) catch |err| switch (err) {
                    error.ProgramContractViolation => {
                        return .{ .failed = try invalidHostReplyFailure(ctx.allocator, "host reply value does not match the declared codec") };
                    },
                    else => return err,
                },
            };
        },
        .rejected => |failure| return .{ .rejected = try failure.clone(ctx.allocator) },
        .failed => |failure| return .{ .failed = try failure.clone(ctx.allocator) },
    }
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
            .usize => |typed| .{ .u64 = typed },
            else => error.ProgramContractViolation,
        },
        .string_list => error.ProgramContractViolation,
    };
}

fn dataValueToRuntimeValue(
    allocator: std.mem.Allocator,
    codec: program_plan.ValueCodec,
    value: host.DataValueV1,
) !RuntimeValue {
    return switch (codec) {
        .unit => switch (value) {
            .null => .{ .value = .none },
            else => error.ProgramContractViolation,
        },
        .bool => switch (value) {
            .bool => |typed| .{ .value = .{ .bool = typed } },
            else => error.ProgramContractViolation,
        },
        .i32 => switch (value) {
            .i64 => |typed| .{ .value = .{ .i32 = std.math.cast(i32, typed) orelse return error.ProgramContractViolation } },
            else => error.ProgramContractViolation,
        },
        .string => switch (value) {
            .string => |typed| .{ .value = .{ .string = try allocator.dupe(u8, typed) }, .owned = true },
            else => error.ProgramContractViolation,
        },
        .usize => switch (value) {
            .u64 => |typed| .{ .value = .{ .usize = std.math.cast(usize, typed) orelse return error.ProgramContractViolation } },
            .i64 => |typed| .{ .value = .{ .usize = std.math.cast(usize, typed) orelse return error.ProgramContractViolation } },
            else => error.ProgramContractViolation,
        },
        .string_list => error.ProgramContractViolation,
    };
}

fn setLocal(
    allocator: std.mem.Allocator,
    locals: []lowered_machine.ProgramValue,
    local_owns_value: []bool,
    index: u16,
    value: RuntimeValue,
) void {
    if (local_owns_value[index]) deinitProgramValue(allocator, &locals[index]);
    locals[index] = value.value;
    local_owns_value[index] = value.owned;
}

fn takeLocalValue(locals: []lowered_machine.ProgramValue, local_owns_value: []bool, index: u16) RuntimeValue {
    const value = RuntimeValue{
        .value = locals[index],
        .owned = local_owns_value[index],
    };
    locals[index] = .none;
    local_owns_value[index] = false;
    return value;
}

fn releaseLocals(allocator: std.mem.Allocator, locals: []lowered_machine.ProgramValue, local_owns_value: []bool) void {
    for (locals, local_owns_value) |*local, *owned| {
        if (owned.*) deinitProgramValue(allocator, local);
        owned.* = false;
    }
}

fn functionLocalCodec(plan: program_plan.ProgramPlan, function: program_plan.FunctionPlan, local_id: u16) ?program_plan.ValueCodec {
    if (local_id >= function.local_count) return null;
    return plan.locals[function.first_local + local_id].codec;
}

fn decodeI32InstructionLiteral(instruction: program_plan.Instruction) i32 {
    const low = @as(u32, instruction.operand);
    const high = @as(u32, instruction.aux) << 16;
    return @bitCast(high | low);
}

fn decodeU32InstructionLiteral(instruction: program_plan.Instruction) u32 {
    const low = @as(u32, instruction.operand);
    const high = @as(u32, instruction.aux) << 16;
    return high | low;
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

fn materializeExecutionValue(allocator: std.mem.Allocator, value: *RuntimeValue) !lowered_machine.ProgramValue {
    if (value.owned) {
        const owned_value = value.value;
        value.* = .{ .value = .none, .owned = false };
        return owned_value;
    }
    return cloneProgramValue(allocator, value.value);
}

fn deinitRuntimeValue(allocator: std.mem.Allocator, value: *RuntimeValue) void {
    if (value.owned) deinitProgramValue(allocator, &value.value);
    value.* = .{ .value = .none, .owned = false };
}

test "runtime local overwrites free replaced owned strings and transfer returned ownership" {
    const CountingAllocator = struct {
        child: std.mem.Allocator,
        alloc_calls: usize = 0,
        free_calls: usize = 0,

        fn init(child: std.mem.Allocator) @This() {
            return .{ .child = child };
        }

        fn allocator(self: *@This()) std.mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .remap = remap,
                    .free = free,
                },
            };
        }

        fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.alloc_calls += 1;
            return self.child.rawAlloc(len, alignment, ret_addr);
        }

        fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.child.rawResize(memory, alignment, new_len, ret_addr);
        }

        fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.child.rawRemap(memory, alignment, new_len, ret_addr);
        }

        fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.free_calls += 1;
            self.child.rawFree(memory, alignment, ret_addr);
        }
    };

    var counting = CountingAllocator.init(std.testing.allocator);
    const allocator = counting.allocator();
    var locals = [_]lowered_machine.ProgramValue{.none};
    var local_owns_value = [_]bool{false};

    setLocal(allocator, &locals, &local_owns_value, 0, .{
        .value = .{ .string = try allocator.dupe(u8, "first") },
        .owned = true,
    });
    try std.testing.expect(local_owns_value[0]);
    const free_calls_before_overwrite = counting.free_calls;

    setLocal(allocator, &locals, &local_owns_value, 0, .{
        .value = .{ .string = try allocator.dupe(u8, "second") },
        .owned = true,
    });
    try std.testing.expectEqual(free_calls_before_overwrite + 1, counting.free_calls);

    var returned = takeLocalValue(&locals, &local_owns_value, 0);
    defer deinitRuntimeValue(allocator, &returned);
    try std.testing.expect(returned.owned);
    try std.testing.expectEqualStrings("second", returned.value.string);
    try std.testing.expect(!local_owns_value[0]);

    const free_calls_before_release = counting.free_calls;
    releaseLocals(allocator, &locals, &local_owns_value);
    try std.testing.expectEqual(free_calls_before_release, counting.free_calls);
}

test "helper frames clone string parameters before returning them" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.helper_param_clone",
        .ir_hash = 0x301,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "echo",
            .value_codec = .string,
            .parameter_count = 1,
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
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{.{ .kind = .return_value, .operand = 0 }},
    };

    var logs = std.ArrayList(host.HostLogEntryV1).empty;
    defer logs.deinit(std.testing.allocator);
    var next_request_id: u64 = 1;
    const decoded = artifact.ArtifactV1{
        .semantic_ir_hash64 = plan.ir_hash,
        .manifest_build_fingerprint = std.mem.zeroes([32]u8),
        .build_fingerprint_blake3_256 = std.mem.zeroes([32]u8),
        .capabilities = &.{},
        .requirement_capability_ids = &.{},
        .functions = plan.functions,
        .requirements = plan.requirements,
        .ops = plan.ops,
        .outputs = plan.outputs,
        .locals = plan.locals,
        .call_args = plan.call_args,
        .blocks = plan.blocks,
        .terminators = plan.terminators,
        .instructions = plan.instructions,
    };
    var ctx = ExecutionContext{
        .allocator = std.testing.allocator,
        .decoded = &decoded,
        .plan = plan,
        .adapter = .{
            .ctx = null,
            .dispatchFn = struct {
                fn dispatch(_: ?*anyopaque, _: std.mem.Allocator, _: host.HostEffectRequestV1) anyerror!host.HostEffectResultV1 {
                    return error.UnexpectedHostDispatch;
                }
            }.dispatch,
        },
        .logs = &logs,
        .next_request_id = &next_request_id,
    };

    const arg = lowered_machine.ProgramValue{ .string = try std.testing.allocator.dupe(u8, "borrowed") };
    defer std.testing.allocator.free(arg.string);

    var returned = try executeFunction(&ctx, 0, &.{arg});
    switch (returned) {
        .value => |*value| {
            defer deinitRuntimeValue(std.testing.allocator, value);
            try std.testing.expect(value.owned);
            try std.testing.expect(value.value == .string);
            try std.testing.expectEqualStrings("borrowed", value.value.string);
            try std.testing.expect(value.value.string.ptr != arg.string.ptr);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "artifact runtime preserves underscore after-hook names" {
    const allocator = std.testing.allocator;

    const single = try afterMethodNameAlloc(allocator, "pick_item");
    defer allocator.free(single);
    try std.testing.expectEqualStrings("afterPick_Item", single);

    const repeated = try afterMethodNameAlloc(allocator, "foo__bar");
    defer allocator.free(repeated);
    try std.testing.expectEqualStrings("afterFoo__Bar", repeated);

    const leading = try afterMethodNameAlloc(allocator, "_foo_bar");
    defer allocator.free(leading);
    try std.testing.expectEqualStrings("after_Foo_Bar", leading);
}

test "artifact runtime decodes after-hook replies with the function result codec" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.after_result_codec_runtime",
        .ir_hash = 0x305,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .result_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "dispatch", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit, .has_after = true }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{ .kind = .call_op, .operand = 0 }},
    };

    const capabilities = [_]artifact.CapabilityV1{.{
        .capability_id = 0,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{
            .{
                .capability_id = 0,
                .op_id = 0,
                .global_op_name = capability_global_tool_call,
                .payload_codec = .unit,
                .result_codec = .unit,
                .plan_op_ordinal = 0,
            },
            .{
                .capability_id = 0,
                .op_id = 1,
                .global_op_name = capability_global_tool_after,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            },
        },
    }};

    var logs = std.ArrayList(host.HostLogEntryV1).empty;
    defer logs.deinit(std.testing.allocator);
    var next_request_id: u64 = 1;
    const decoded = artifact.ArtifactV1{
        .semantic_ir_hash64 = plan.ir_hash,
        .manifest_build_fingerprint = std.mem.zeroes([32]u8),
        .build_fingerprint_blake3_256 = std.mem.zeroes([32]u8),
        .capabilities = &capabilities,
        .requirement_capability_ids = &.{0},
        .functions = plan.functions,
        .requirements = plan.requirements,
        .ops = plan.ops,
        .outputs = plan.outputs,
        .locals = plan.locals,
        .call_args = plan.call_args,
        .blocks = plan.blocks,
        .terminators = plan.terminators,
        .instructions = plan.instructions,
    };
    var after_calls: usize = 0;
    var ctx = ExecutionContext{
        .allocator = std.testing.allocator,
        .decoded = &decoded,
        .plan = plan,
        .adapter = .{
            .ctx = &after_calls,
            .dispatchFn = struct {
                fn dispatch(ctx_ptr: ?*anyopaque, allocator: std.mem.Allocator, request: host.HostEffectRequestV1) anyerror!host.HostEffectResultV1 {
                    const counter: *usize = @ptrCast(@alignCast(ctx_ptr.?));
                    const tool_call = request.body.tool_call;
                    if (std.mem.eql(u8, tool_call.op_name, "dispatch")) {
                        return .{
                            .schema_version = 1,
                            .request_id = request.request_id,
                            .body = .{ .success = .{
                                .tool_id = try allocator.dupe(u8, tool_call.tool_id),
                                .call_id = 44,
                                .control = .@"resume",
                                .value = .null,
                                .owns_tool_id = true,
                            } },
                        };
                    }
                    if (std.mem.eql(u8, tool_call.op_name, "afterDispatch")) {
                        counter.* += 1;
                        return .{
                            .schema_version = 1,
                            .request_id = request.request_id,
                            .body = .{ .success = .{
                                .tool_id = try allocator.dupe(u8, tool_call.tool_id),
                                .call_id = tool_call.call_id,
                                .control = .@"resume",
                                .value = .{ .string = try allocator.dupe(u8, "wrapped-transform") },
                                .owns_tool_id = true,
                            } },
                        };
                    }
                    return error.UnexpectedHostDispatch;
                }
            }.dispatch,
        },
        .logs = &logs,
        .next_request_id = &next_request_id,
    };

    var returned = try executeFunction(&ctx, 0, &.{});
    switch (returned) {
        .value => |*value| {
            defer deinitRuntimeValue(std.testing.allocator, value);
            try std.testing.expect(value.owned);
            try std.testing.expectEqualStrings("wrapped-transform", value.value.string);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), after_calls);
}

test "artifact runtime executes add_i32 instructions" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.add_i32",
        .ir_hash = 0x302,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "add",
            .value_codec = .i32,
            .parameter_count = 2,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 3,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
        },
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .add_i32, .dst = 2, .operand = 0, .aux = 1 },
            .{ .kind = .return_value, .operand = 2 },
        },
    };

    var logs = std.ArrayList(host.HostLogEntryV1).empty;
    defer logs.deinit(std.testing.allocator);
    var next_request_id: u64 = 1;
    const decoded = artifact.ArtifactV1{
        .semantic_ir_hash64 = plan.ir_hash,
        .manifest_build_fingerprint = std.mem.zeroes([32]u8),
        .build_fingerprint_blake3_256 = std.mem.zeroes([32]u8),
        .capabilities = &.{},
        .requirement_capability_ids = &.{},
        .functions = plan.functions,
        .requirements = plan.requirements,
        .ops = plan.ops,
        .outputs = plan.outputs,
        .locals = plan.locals,
        .call_args = plan.call_args,
        .blocks = plan.blocks,
        .terminators = plan.terminators,
        .instructions = plan.instructions,
    };
    var ctx = ExecutionContext{
        .allocator = std.testing.allocator,
        .decoded = &decoded,
        .plan = plan,
        .adapter = .{
            .ctx = null,
            .dispatchFn = struct {
                fn dispatch(_: ?*anyopaque, _: std.mem.Allocator, _: host.HostEffectRequestV1) anyerror!host.HostEffectResultV1 {
                    return error.UnexpectedHostDispatch;
                }
            }.dispatch,
        },
        .logs = &logs,
        .next_request_id = &next_request_id,
    };

    var returned = try executeFunction(&ctx, 0, &.{
        .{ .i32 = 20 },
        .{ .i32 = 22 },
    });
    switch (returned) {
        .value => |*value| {
            defer deinitRuntimeValue(std.testing.allocator, value);
            try std.testing.expect(!value.owned);
            try std.testing.expectEqual(@as(i32, 42), value.value.i32);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "artifact runtime returns ProgramContractViolation on add_i32 overflow" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.add_i32_overflow",
        .ir_hash = 0x303,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "add",
            .value_codec = .i32,
            .parameter_count = 2,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 3,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
        },
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .add_i32, .dst = 2, .operand = 0, .aux = 1 },
            .{ .kind = .return_value, .operand = 2 },
        },
    };

    var logs = std.ArrayList(host.HostLogEntryV1).empty;
    defer logs.deinit(std.testing.allocator);
    var next_request_id: u64 = 1;
    const decoded = artifact.ArtifactV1{
        .semantic_ir_hash64 = plan.ir_hash,
        .manifest_build_fingerprint = std.mem.zeroes([32]u8),
        .build_fingerprint_blake3_256 = std.mem.zeroes([32]u8),
        .capabilities = &.{},
        .requirement_capability_ids = &.{},
        .functions = plan.functions,
        .requirements = plan.requirements,
        .ops = plan.ops,
        .outputs = plan.outputs,
        .locals = plan.locals,
        .call_args = plan.call_args,
        .blocks = plan.blocks,
        .terminators = plan.terminators,
        .instructions = plan.instructions,
    };
    var ctx = ExecutionContext{
        .allocator = std.testing.allocator,
        .decoded = &decoded,
        .plan = plan,
        .adapter = .{
            .ctx = null,
            .dispatchFn = struct {
                fn dispatch(_: ?*anyopaque, _: std.mem.Allocator, _: host.HostEffectRequestV1) anyerror!host.HostEffectResultV1 {
                    return error.UnexpectedHostDispatch;
                }
            }.dispatch,
        },
        .logs = &logs,
        .next_request_id = &next_request_id,
    };

    try std.testing.expectError(error.ProgramContractViolation, executeFunction(&ctx, 0, &.{
        .{ .i32 = std.math.maxInt(i32) },
        .{ .i32 = 1 },
    }));
}

test "artifact runtime decodes hexadecimal const_usize literals" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.const_usize_hex",
        .ir_hash = 0x304,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "hexUsize",
            .value_codec = .usize,
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
            .instruction_count = 2,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .usize }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .const_usize, .dst = 0, .string_literal = "0xff" },
            .{ .kind = .return_value, .operand = 0 },
        },
    };

    var logs = std.ArrayList(host.HostLogEntryV1).empty;
    defer logs.deinit(std.testing.allocator);
    var next_request_id: u64 = 1;
    const decoded = artifact.ArtifactV1{
        .semantic_ir_hash64 = plan.ir_hash,
        .manifest_build_fingerprint = std.mem.zeroes([32]u8),
        .build_fingerprint_blake3_256 = std.mem.zeroes([32]u8),
        .capabilities = &.{},
        .requirement_capability_ids = &.{},
        .functions = plan.functions,
        .requirements = plan.requirements,
        .ops = plan.ops,
        .outputs = plan.outputs,
        .locals = plan.locals,
        .call_args = plan.call_args,
        .blocks = plan.blocks,
        .terminators = plan.terminators,
        .instructions = plan.instructions,
    };
    var ctx = ExecutionContext{
        .allocator = std.testing.allocator,
        .decoded = &decoded,
        .plan = plan,
        .adapter = .{
            .ctx = null,
            .dispatchFn = struct {
                fn dispatch(_: ?*anyopaque, _: std.mem.Allocator, _: host.HostEffectRequestV1) anyerror!host.HostEffectResultV1 {
                    return error.UnexpectedHostDispatch;
                }
            }.dispatch,
        },
        .logs = &logs,
        .next_request_id = &next_request_id,
    };

    var returned = try executeFunction(&ctx, 0, &.{});
    switch (returned) {
        .value => |*value| {
            defer deinitRuntimeValue(std.testing.allocator, value);
            try std.testing.expect(!value.owned);
            try std.testing.expectEqual(@as(usize, 0xff), value.value.usize);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "artifact runtime returns ProgramContractViolation on add_const_i32 overflow" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.add_const_i32_overflow",
        .ir_hash = 0x304,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "addConst",
            .value_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .i32 },
        },
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .add_const_i32, .dst = 1, .operand = 0, .aux = 1 },
            .{ .kind = .return_value, .operand = 1 },
        },
    };

    var logs = std.ArrayList(host.HostLogEntryV1).empty;
    defer logs.deinit(std.testing.allocator);
    var next_request_id: u64 = 1;
    const decoded = artifact.ArtifactV1{
        .semantic_ir_hash64 = plan.ir_hash,
        .manifest_build_fingerprint = std.mem.zeroes([32]u8),
        .build_fingerprint_blake3_256 = std.mem.zeroes([32]u8),
        .capabilities = &.{},
        .requirement_capability_ids = &.{},
        .functions = plan.functions,
        .requirements = plan.requirements,
        .ops = plan.ops,
        .outputs = plan.outputs,
        .locals = plan.locals,
        .call_args = plan.call_args,
        .blocks = plan.blocks,
        .terminators = plan.terminators,
        .instructions = plan.instructions,
    };
    var ctx = ExecutionContext{
        .allocator = std.testing.allocator,
        .decoded = &decoded,
        .plan = plan,
        .adapter = .{
            .ctx = null,
            .dispatchFn = struct {
                fn dispatch(_: ?*anyopaque, _: std.mem.Allocator, _: host.HostEffectRequestV1) anyerror!host.HostEffectResultV1 {
                    return error.UnexpectedHostDispatch;
                }
            }.dispatch,
        },
        .logs = &logs,
        .next_request_id = &next_request_id,
    };

    try std.testing.expectError(error.ProgramContractViolation, executeFunction(&ctx, 0, &.{
        .{ .i32 = std.math.maxInt(i32) },
    }));
}

fn deinitProgramValue(allocator: std.mem.Allocator, value: *lowered_machine.ProgramValue) void {
    switch (value.*) {
        .string => |typed| allocator.free(typed),
        else => {},
    }
    value.* = .none;
}
