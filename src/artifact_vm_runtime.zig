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
        .terminal => |value| blk: {
            var runtime_value = value;
            errdefer deinitRuntimeValue(allocator, &runtime_value);
            var owned_value = try materializeExecutionValue(allocator, &runtime_value);
            errdefer deinitProgramValue(allocator, &owned_value);
            break :blk .{
                .completed = .{
                    .value = owned_value,
                    .logs = try logs.toOwnedSlice(allocator),
                },
            };
        },
        .value => |value| blk: {
            var runtime_value = value;
            errdefer deinitRuntimeValue(allocator, &runtime_value);
            var owned_value = try materializeExecutionValue(allocator, &runtime_value);
            errdefer deinitProgramValue(allocator, &owned_value);
            break :blk .{
                .completed = .{
                    .value = owned_value,
                    .logs = try logs.toOwnedSlice(allocator),
                },
            };
        },
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

const RuntimeValue = struct {
    value: lowered_machine.ProgramValue,
    owned: bool = false,
};

const FunctionResult = union(enum) {
    failed: host.FailureV1,
    rejected: host.FailureV1,
    terminal: RuntimeValue,
    value: RuntimeValue,
};

const ExecutionContext = struct {
    allocator: std.mem.Allocator,
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

    while (true) {
        const block = ctx.plan.blocks[current_block_index];
        const instruction_end = block.first_instruction + block.instruction_count;
        while (instruction_index < instruction_end) : (instruction_index += 1) {
            const instruction = ctx.plan.instructions[instruction_index];
            switch (instruction.kind) {
                .add_const_i32 => setLocal(
                    ctx.allocator,
                    locals,
                    local_owns_value,
                    instruction.dst,
                    .{
                        .value = switch (locals[instruction.operand]) {
                            .i32 => |typed| .{ .i32 = typed + @as(i32, @intCast(instruction.aux)) },
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
                        .terminal => |value| return .{ .terminal = value },
                        .rejected => |failure| return .{ .rejected = failure },
                        .failed => |failure| return .{ .failed = failure },
                    }
                },
                .call_op => {
                    const op = ctx.plan.ops[instruction.operand];
                    const payload = if (op.payload_codec == .unit) .none else locals[instruction.aux];
                    const op_result = try callHostOp(ctx, instruction.operand, payload);
                    switch (op_result) {
                        .resumed => |value| {
                            if (op.resume_codec != .unit) setLocal(ctx.allocator, locals, local_owns_value, instruction.dst, value);
                        },
                        .terminal => |value| return .{ .terminal = value },
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
                .const_i32 => setLocal(ctx.allocator, locals, local_owns_value, instruction.dst, .{ .value = .{ .i32 = decodeI32InstructionLiteral(instruction) } }),
                .const_string => setLocal(ctx.allocator, locals, local_owns_value, instruction.dst, .{ .value = .{ .string = instruction.string_literal } }),
                .return_value => return_local = instruction.operand,
                .sub_one => setLocal(
                    ctx.allocator,
                    locals,
                    local_owns_value,
                    instruction.dst,
                    .{
                        .value = switch (locals[instruction.operand]) {
                            .i32 => |typed| .{ .i32 = typed - 1 },
                            .usize => |typed| .{ .usize = typed - 1 },
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
            .return_unit => return .{ .value = .{ .value = .none } },
            .return_value => return .{ .value = takeLocalValue(locals, local_owns_value, return_local orelse return error.ProgramContractViolation) },
        }
    }
}

const OpDispatchResult = union(enum) {
    failed: host.FailureV1,
    rejected: host.FailureV1,
    resumed: RuntimeValue,
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

    var response: host.HostEffectResultV1 = ctx.adapter.dispatch(ctx.allocator, request) catch |err| .{
        .request_id = request.request_id,
        .body = .{ .failed = .{
            .code = try ctx.allocator.dupe(u8, "provider_failure"),
            .message = try std.fmt.allocPrint(ctx.allocator, "host_adapter_dispatch:{s}", .{@errorName(err)}),
        } },
    };
    defer response.deinit(ctx.allocator);
    if (response.schema_version != 1) return error.ProgramContractViolation;
    if (response.request_id != request.request_id) return error.ProgramContractViolation;
    switch (response.body) {
        .success => |tool_result| {
            const tool_call = request.body.tool_call;
            if (!std.mem.eql(u8, tool_result.tool_id, tool_call.tool_id)) return error.ProgramContractViolation;
            if (tool_result.call_id != tool_call.call_id) return error.ProgramContractViolation;
        },
        else => {},
    }

    try ctx.logs.append(ctx.allocator, .{
        .request = try request.clone(ctx.allocator),
        .result = try response.clone(ctx.allocator),
    });

    return switch (response.body) {
        .success => |tool_result| blk: {
            if (!hostControlMatchesOpMode(op.mode, tool_result.control)) return error.ProgramContractViolation;
            break :blk switch (tool_result.control) {
                .@"resume" => .{ .resumed = try dataValueToRuntimeValue(ctx.allocator, op.resume_codec, tool_result.value) },
                .return_now, .abort => .{
                    .terminal = try dataValueToRuntimeValue(
                        ctx.allocator,
                        artifact.terminalResultCodecForOp(ctx.plan, op_index) catch return error.ProgramContractViolation,
                        tool_result.value,
                    ),
                },
            };
        },
        .rejected => |failure| .{ .rejected = try failure.clone(ctx.allocator) },
        .failed => |failure| .{ .failed = try failure.clone(ctx.allocator) },
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
    const capability_op = findCapabilityOpByPlanOrdinal(capability.ops, op_index - requirement.first_op) orelse return null;
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

fn findCapabilityOpByPlanOrdinal(ops: []const artifact.CapabilityOpV1, plan_op_ordinal: u16) ?artifact.CapabilityOpV1 {
    for (ops) |op| {
        if (op.plan_op_ordinal == plan_op_ordinal) return op;
    }
    return null;
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
            .ctx = undefined,
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

fn deinitProgramValue(allocator: std.mem.Allocator, value: *lowered_machine.ProgramValue) void {
    switch (value.*) {
        .string => |typed| allocator.free(typed),
        else => {},
    }
    value.* = .none;
}
