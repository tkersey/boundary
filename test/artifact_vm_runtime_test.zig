const conformance = @import("host_adapter_v1_conformance");
const example = @import("example_open_row_state_writer");
const internal_program_plan = @import("shift").internal_program_plan;
const shift_compile = @import("shift_compile");
const shift_vm = @import("shift_vm");
const std = @import("std");

const RuntimeContext = struct {
    state: i32,
    writer_items: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (self.writer_items.items) |item| allocator.free(item);
        self.writer_items.deinit(allocator);
    }
};

const LoweredStateHandler = struct {
    value: i32,

    /// Return the current retained state value.
    pub fn get(self: *@This()) anyerror!i32 {
        return self.value;
    }

    /// Replace the retained state value.
    pub fn set(self: *@This(), value: i32) anyerror!void {
        self.value = value;
    }

    /// Finish the lowered state handler and surface the final state.
    pub fn finish(self: *@This()) i32 {
        return self.value;
    }
};

const LoweredWriterHandler = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList([]u8) = .empty,

    /// Record one retained writer output.
    pub fn tell(self: *@This(), value: []const u8) anyerror!void {
        try self.items.append(self.allocator, try self.allocator.dupe(u8, value));
    }

    /// Finish the lowered writer handler and clone its buffered outputs.
    pub fn finish(self: *@This()) anyerror![][]const u8 {
        const outputs = try self.allocator.alloc([]const u8, self.items.items.len);
        for (self.items.items, outputs) |item, *output| {
            output.* = try self.allocator.dupe(u8, item);
        }
        return outputs;
    }

    /// Release retained writer outputs buffered for parity testing.
    pub fn deinit(self: *@This()) void {
        for (self.items.items) |item| self.allocator.free(item);
        self.items.deinit(self.allocator);
    }
};

const LoweredHandlers = struct {
    state: LoweredStateHandler,
    writer: LoweredWriterHandler,
};

fn deinitLoweredWriterOutputs(allocator: std.mem.Allocator, outputs: [][]const u8) void {
    for (outputs) |item| allocator.free(item);
    allocator.free(outputs);
}

fn expectCompleted(result: *shift_vm.runtime.RunArtifactResultV1) !*shift_vm.runtime.ExecutionResultV1 {
    return switch (result.*) {
        .completed => |*completed| completed,
        else => error.TestUnexpectedResult,
    };
}

fn dispatch(ctx: *anyopaque, allocator: std.mem.Allocator, request: shift_vm.host_adapter.HostEffectRequestV1) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    const runtime_ctx: *RuntimeContext = @ptrCast(@alignCast(ctx));
    const tool_call = request.body.tool_call;
    if (std.mem.eql(u8, tool_call.op_name, "get")) {
        return .{
            .request_id = request.request_id,
            .body = .{ .success = .{
                .tool_id = try allocator.dupe(u8, tool_call.tool_id),
                .call_id = tool_call.call_id,
                .control = shift_vm.host_adapter.ToolControlV1.@"resume",
                .value = .{ .i64 = runtime_ctx.state },
                .owns_tool_id = true,
            } },
        };
    }
    if (std.mem.eql(u8, tool_call.op_name, "set")) {
        runtime_ctx.state = @intCast(tool_call.arguments.i64);
        return .{
            .request_id = request.request_id,
            .body = .{ .success = .{
                .tool_id = try allocator.dupe(u8, tool_call.tool_id),
                .call_id = tool_call.call_id,
                .control = shift_vm.host_adapter.ToolControlV1.@"resume",
                .value = .null,
                .owns_tool_id = true,
            } },
        };
    }
    if (std.mem.eql(u8, tool_call.op_name, "tell")) {
        try runtime_ctx.writer_items.append(allocator, try allocator.dupe(u8, tool_call.arguments.string));
        return .{
            .request_id = request.request_id,
            .body = .{ .success = .{
                .tool_id = try allocator.dupe(u8, tool_call.tool_id),
                .call_id = tool_call.call_id,
                .control = shift_vm.host_adapter.ToolControlV1.@"resume",
                .value = .null,
                .owns_tool_id = true,
            } },
        };
    }
    return .{
        .request_id = request.request_id,
        .body = .{ .failed = .{
            .code = try allocator.dupe(u8, "unknown_op"),
            .message = try allocator.dupe(u8, tool_call.op_name),
            .owns_code = true,
            .owns_message = true,
        } },
    };
}

const string_dispatch_context = struct {};
const IntegerDispatchContext = struct {
    value: i64,
};

const UnsignedIntegerDispatchContext = struct {
    value: u64,
    seen_argument: ?u64 = null,
};

const FixedControlDispatchContext = struct {
    control: shift_vm.host_adapter.ToolControlV1,
    string_value: []const u8 = "early",
    use_null_value: bool = false,
};

fn dispatchManifestOpIdentityStringResults(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    _ = ctx;
    try std.testing.expectEqual(@as(u16, 7), request.capability_id);
    try std.testing.expectEqualStrings("generated/tooling@v1", request.body.tool_call.tool_id);
    const value = if (std.mem.eql(u8, request.body.tool_call.op_name, "first")) blk: {
        try std.testing.expectEqual(@as(u16, 4), request.op_id);
        break :blk "keepalive0";
    } else if (std.mem.eql(u8, request.body.tool_call.op_name, "second")) blk: {
        try std.testing.expectEqual(@as(u16, 6), request.op_id);
        break :blk "overwrite0";
    } else return error.UnexpectedOpName;
    return .{
        .request_id = request.request_id,
        .body = .{ .success = .{
            .tool_id = try allocator.dupe(u8, request.body.tool_call.tool_id),
            .call_id = request.body.tool_call.call_id,
            .control = .@"resume",
            .value = .{ .string = try allocator.dupe(u8, value) },
            .owns_tool_id = true,
            .value_ownership = .deep,
        } },
    };
}

fn dispatchHelperStringOwnership(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    _ = ctx;
    try std.testing.expectEqual(@as(u16, 11), request.capability_id);
    try std.testing.expectEqualStrings("generated/primary@v1", request.body.tool_call.tool_id);
    const value = if (std.mem.eql(u8, request.body.tool_call.op_name, "first")) blk: {
        try std.testing.expectEqual(@as(u16, 0), request.op_id);
        break :blk "alpha";
    } else if (std.mem.eql(u8, request.body.tool_call.op_name, "second")) blk: {
        try std.testing.expectEqual(@as(u16, 1), request.op_id);
        break :blk "omega";
    } else return error.UnexpectedOpName;
    return .{
        .request_id = request.request_id,
        .body = .{ .success = .{
            .tool_id = try allocator.dupe(u8, request.body.tool_call.tool_id),
            .call_id = request.body.tool_call.call_id,
            .control = .@"resume",
            .value = .{ .string = try allocator.dupe(u8, value) },
            .owns_tool_id = true,
            .value_ownership = .deep,
        } },
    };
}

fn dispatchTerminalReturn(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    _ = ctx;
    try std.testing.expectEqual(@as(u16, 33), request.capability_id);
    try std.testing.expectEqual(@as(u16, 8), request.op_id);
    return .{
        .request_id = request.request_id,
        .body = .{ .success = .{
            .tool_id = try allocator.dupe(u8, request.body.tool_call.tool_id),
            .call_id = request.body.tool_call.call_id,
            .control = .return_now,
            .value = .{ .string = try allocator.dupe(u8, "early") },
            .owns_tool_id = true,
            .value_ownership = .deep,
        } },
    };
}

fn dispatchTerminalAbort(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    _ = ctx;
    try std.testing.expectEqual(@as(u16, 33), request.capability_id);
    try std.testing.expectEqual(@as(u16, 8), request.op_id);
    return .{
        .request_id = request.request_id,
        .body = .{ .success = .{
            .tool_id = try allocator.dupe(u8, request.body.tool_call.tool_id),
            .call_id = request.body.tool_call.call_id,
            .control = .abort,
            .value = .{ .string = try allocator.dupe(u8, "early-abort") },
            .owns_tool_id = true,
            .value_ownership = .deep,
        } },
    };
}

fn dispatchIntegerResult(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    const runtime_ctx: *IntegerDispatchContext = @ptrCast(@alignCast(ctx));
    return .{
        .request_id = request.request_id,
        .body = .{ .success = .{
            .tool_id = try allocator.dupe(u8, request.body.tool_call.tool_id),
            .call_id = request.body.tool_call.call_id,
            .control = .@"resume",
            .value = .{ .i64 = runtime_ctx.value },
            .owns_tool_id = true,
        } },
    };
}

fn dispatchUnsignedIntegerRoundTrip(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    const runtime_ctx: *UnsignedIntegerDispatchContext = @ptrCast(@alignCast(ctx));
    if (request.op_id == 1) {
        runtime_ctx.seen_argument = switch (request.body.tool_call.arguments) {
            .u64 => |typed| typed,
            else => return error.TestUnexpectedResult,
        };
    }
    return .{
        .request_id = request.request_id,
        .body = .{ .success = .{
            .tool_id = try allocator.dupe(u8, request.body.tool_call.tool_id),
            .call_id = request.body.tool_call.call_id,
            .control = .@"resume",
            .value = .{ .u64 = runtime_ctx.value },
            .owns_tool_id = true,
        } },
    };
}

fn dispatchFixedControlResult(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    const runtime_ctx: *FixedControlDispatchContext = @ptrCast(@alignCast(ctx));
    return .{
        .request_id = request.request_id,
        .body = .{ .success = .{
            .tool_id = try allocator.dupe(u8, request.body.tool_call.tool_id),
            .call_id = request.body.tool_call.call_id,
            .control = runtime_ctx.control,
            .value = if (runtime_ctx.use_null_value)
                .null
            else
                .{ .string = try allocator.dupe(u8, runtime_ctx.string_value) },
            .owns_tool_id = true,
            .value_ownership = if (runtime_ctx.use_null_value) .borrowed else .deep,
        } },
    };
}

fn dispatchMismatchedSuccess(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    const runtime_ctx: *IntegerDispatchContext = @ptrCast(@alignCast(ctx));
    return .{
        .request_id = request.request_id,
        .body = .{ .success = .{
            .tool_id = try allocator.dupe(u8, if (runtime_ctx.value == 0) "wrong/tool@v1" else request.body.tool_call.tool_id),
            .call_id = if (runtime_ctx.value == 0) request.body.tool_call.call_id else request.body.tool_call.call_id + 1,
            .control = .@"resume",
            .value = .{ .i64 = 1 },
            .owns_tool_id = true,
        } },
    };
}

fn dispatchWrongSchemaVersion(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    _ = ctx;
    return .{
        .schema_version = 2,
        .request_id = request.request_id,
        .body = .{ .success = .{
            .tool_id = try allocator.dupe(u8, request.body.tool_call.tool_id),
            .call_id = request.body.tool_call.call_id,
            .control = .@"resume",
            .value = .{ .i64 = 1 },
            .owns_tool_id = true,
        } },
    };
}

fn dispatchNonNullUnitResult(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    _ = ctx;
    return .{
        .request_id = request.request_id,
        .body = .{ .success = .{
            .tool_id = try allocator.dupe(u8, request.body.tool_call.tool_id),
            .call_id = request.body.tool_call.call_id,
            .control = .@"resume",
            .value = .{ .string = try allocator.dupe(u8, "not-null") },
            .owns_tool_id = true,
            .value_ownership = .deep,
        } },
    };
}

fn encodeSingleResumeArtifact(
    allocator: std.mem.Allocator,
    codec: internal_program_plan.ValueCodec,
    build_seed: []const u8,
) ![]u8 {
    const plan: internal_program_plan.ProgramPlan = .{
        .label = "artifact.runtime.integer_boundary",
        .ir_hash = 0xa1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = codec,
            .parameter_count = 0,
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
            .instruction_count = 2,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "value", .mode = .transform, .payload_codec = .unit, .resume_codec = codec }},
        .outputs = &.{},
        .locals = &.{.{ .codec = codec }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .call_op, .dst = 0, .operand = 0 },
            .{ .kind = .return_value, .operand = 0 },
        },
    };
    const capabilities = [_]shift_vm.CapabilityV1{.{
        .capability_id = 5,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{.{
            .capability_id = 5,
            .op_id = 0,
            .global_op_name = "tool.call",
            .payload_codec = .unit,
            .result_codec = shift_vm.artifact.mapPlanCodecToCapabilityCodec(codec),
            .plan_op_ordinal = 0,
        }},
    }};

    return shift_vm.artifact.encodeProgramPlan(allocator, plan, .{
        .build_fingerprint_blake3_256 = shift_vm.artifact.buildFingerprintFromSeed(build_seed),
        .capabilities = &capabilities,
    });
}

fn encodeSingleStringArtifact(
    allocator: std.mem.Allocator,
    mode: internal_program_plan.ControlMode,
    resume_codec: internal_program_plan.ValueCodec,
    build_seed: []const u8,
) ![]u8 {
    const plan: internal_program_plan.ProgramPlan = .{
        .label = "artifact.runtime.control_mode_contract",
        .ir_hash = 0xa2,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
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
            .instruction_count = 3,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "value", .mode = mode, .payload_codec = .unit, .resume_codec = resume_codec }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .const_string, .dst = 0, .string_literal = "fallback" },
            .{ .kind = .call_op, .dst = 0, .operand = 0 },
            .{ .kind = .return_value, .operand = 0 },
        },
    };
    const capability_result_codec = switch (mode) {
        .transform => shift_vm.artifact.mapPlanCodecToCapabilityCodec(resume_codec),
        .choice, .abort => .string,
    };
    const capabilities = [_]shift_vm.CapabilityV1{.{
        .capability_id = 5,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{.{
            .capability_id = 5,
            .op_id = 0,
            .global_op_name = "tool.call",
            .payload_codec = .unit,
            .result_codec = capability_result_codec,
            .plan_op_ordinal = 0,
        }},
    }};

    return shift_vm.artifact.encodeProgramPlan(allocator, plan, .{
        .build_fingerprint_blake3_256 = shift_vm.artifact.buildFingerprintFromSeed(build_seed),
        .capabilities = &capabilities,
    });
}

test "ArtifactV1 runtime executes transform-only lowered programs with sequential request ids" {
    const bytes = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "artifact-runtime-test",
            .capabilities = &.{},
        },
    );
    defer std.testing.allocator.free(bytes);

    var context = RuntimeContext{ .state = 5 };
    defer context.deinit(std.testing.allocator);

    var run_result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatch,
    });
    defer run_result.deinit(std.testing.allocator);
    const result = try expectCompleted(&run_result);

    try std.testing.expectEqualStrings("done", result.value.string);
    try std.testing.expectEqual(@as(i32, 6), context.state);
    try std.testing.expectEqual(@as(usize, 2), context.writer_items.items.len);
    try std.testing.expectEqualStrings("query=artifact-search", context.writer_items.items[0]);
    try std.testing.expectEqualStrings("workflow=queued", context.writer_items.items[1]);
    try std.testing.expectEqual(@as(usize, 4), result.logs.len);
    try conformance.assertSequentialRequestIds(result.logs);
    try conformance.assertToolCallShape(result.logs[0], "generated/state@v1", "get");
    try conformance.assertToolCallShape(result.logs[1], "generated/state@v1", "set");
    try conformance.assertToolCallShape(result.logs[2], "generated/writer@v1", "tell");
    try conformance.assertToolCallShape(result.logs[3], "generated/writer@v1", "tell");
}

test "ArtifactV1 runtime matches lowered runner outputs on open_row_state_writer" {
    var lowered_runtime = @import("shift").Runtime.init(std.testing.allocator);
    defer lowered_runtime.deinit();
    var handlers: LoweredHandlers = .{
        .state = .{ .value = 5 },
        .writer = .{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const lowered_result = try example.CompiledProgram.run(&lowered_runtime, &handlers);
    defer deinitLoweredWriterOutputs(std.testing.allocator, lowered_result.outputs.writer);

    const bytes = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "artifact-runtime-parity",
            .capabilities = &.{},
        },
    );
    defer std.testing.allocator.free(bytes);

    var context = RuntimeContext{ .state = 5 };
    defer context.deinit(std.testing.allocator);

    var run_result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatch,
    });
    defer run_result.deinit(std.testing.allocator);
    const artifact_result = try expectCompleted(&run_result);

    try std.testing.expectEqualStrings(lowered_result.value, artifact_result.value.string);
    try std.testing.expectEqual(lowered_result.outputs.state, context.state);
    try std.testing.expectEqual(lowered_result.outputs.writer.len, context.writer_items.items.len);
    for (lowered_result.outputs.writer, context.writer_items.items) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
    }
}

test "ArtifactV1 runtime preserves sparse op identity across reordered manifest rows and keeps resumed strings alive" {
    const build_fingerprint = shift_vm.artifact.buildFingerprintFromSeed("artifact-runtime-nonzero-capability");
    const plan: internal_program_plan.ProgramPlan = .{
        .label = "artifact.runtime.string_resume",
        .ir_hash = 0x81,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 3,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 2 }},
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "first", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
            .{ .requirement_index = 0, .op_name = "second", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
        },
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .string } },
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .call_op, .dst = 0, .operand = 0 },
            .{ .kind = .call_op, .dst = 1, .operand = 1 },
            .{ .kind = .return_value, .operand = 0 },
        },
    };
    const capabilities = [_]shift_vm.CapabilityV1{.{
        .capability_id = 7,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{
            .{
                .capability_id = 7,
                .op_id = 6,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 1,
            },
            .{
                .capability_id = 7,
                .op_id = 4,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            },
        },
    }};

    const bytes = try shift_vm.artifact.encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(bytes);

    var context = string_dispatch_context{};
    var run_result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchManifestOpIdentityStringResults,
    });
    defer run_result.deinit(std.testing.allocator);
    const result = try expectCompleted(&run_result);

    try std.testing.expectEqualStrings("keepalive0", result.value.string);
    try std.testing.expectEqual(@as(usize, 2), result.logs.len);
    try std.testing.expectEqual(@as(u16, 7), result.logs[0].request.capability_id);
    try std.testing.expectEqual(@as(u16, 4), result.logs[0].request.op_id);
    try std.testing.expectEqual(@as(u16, 6), result.logs[1].request.op_id);
}

test "ArtifactV1 runtime clones helper string parameters before caller overwrites originals" {
    const build_fingerprint = shift_vm.artifact.buildFingerprintFromSeed("artifact-runtime-helper-string-ownership");
    const plan: internal_program_plan.ProgramPlan = .{
        .label = "artifact.runtime.helper_string_ownership",
        .ir_hash = 0xa1,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "entry",
                .value_codec = .string,
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 2,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 4,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .string,
                .parameter_count = 1,
                .first_requirement = 1,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 2,
                .local_count = 1,
                .first_block = 1,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 4,
                .instruction_count = 1,
            },
        },
        .requirements = &.{.{ .label = "primary", .first_op = 0, .op_count = 2 }},
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "first", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
            .{ .requirement_index = 0, .op_name = "second", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
        },
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .string }, .{ .codec = .string } },
        .call_args = &.{0},
        .blocks = &.{
            .{ .first_instruction = 0, .instruction_count = 4, .terminator_index = 0 },
            .{ .first_instruction = 4, .instruction_count = 1, .terminator_index = 1 },
        },
        .terminators = &.{
            .{ .kind = .return_value },
            .{ .kind = .return_value },
        },
        .instructions = &.{
            .{ .kind = .call_op, .dst = 0, .operand = 0 },
            .{ .kind = .call_helper, .dst = 1, .operand = 1, .aux = 0 },
            .{ .kind = .call_op, .dst = 0, .operand = 1 },
            .{ .kind = .return_value, .operand = 1 },
            .{ .kind = .return_value, .operand = 0 },
        },
    };
    const capabilities = [_]shift_vm.CapabilityV1{.{
        .capability_id = 11,
        .kind = .tool,
        .label = "generated/primary@v1",
        .ops = &.{
            .{
                .capability_id = 11,
                .op_id = 0,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            },
            .{
                .capability_id = 11,
                .op_id = 1,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 1,
            },
        },
    }};

    const bytes = try shift_vm.artifact.encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(bytes);

    const PoisonAllocator = struct {
        child: std.mem.Allocator,

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
            @memset(memory, 0xdd);
            self.child.rawFree(memory, alignment, ret_addr);
        }
    };

    var poison = PoisonAllocator{ .child = std.testing.allocator };
    const allocator = poison.allocator();
    var context = string_dispatch_context{};

    var run_result = try shift_vm.runtime.runArtifact(allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchHelperStringOwnership,
    });
    defer run_result.deinit(allocator);
    const result = try expectCompleted(&run_result);

    try std.testing.expectEqualStrings("alpha", result.value.string);
    try std.testing.expectEqual(@as(usize, 2), result.logs.len);
    try std.testing.expectEqual(@as(u16, 0), result.logs[0].request.op_id);
    try std.testing.expectEqual(@as(u16, 1), result.logs[1].request.op_id);
}

test "ArtifactV1 runtime decodes terminal string results for later requirement ops" {
    const build_fingerprint = shift_vm.artifact.buildFingerprintFromSeed("artifact-runtime-terminal-codec");
    const plan: internal_program_plan.ProgramPlan = .{
        .label = "artifact.runtime.terminal_later_op",
        .ir_hash = 0x91,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 3,
        }},
        .requirements = &.{
            .{ .label = "primary", .first_op = 0, .op_count = 2 },
            .{ .label = "terminal", .first_op = 2, .op_count = 1 },
        },
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "unused-a", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit },
            .{ .requirement_index = 0, .op_name = "unused-b", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit },
            .{ .requirement_index = 1, .op_name = "stop", .mode = .abort, .payload_codec = .unit, .resume_codec = .unit },
        },
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .const_string, .dst = 0, .string_literal = "fallback" },
            .{ .kind = .call_op, .operand = 2 },
            .{ .kind = .return_value, .operand = 0 },
        },
    };
    const capabilities = [_]shift_vm.CapabilityV1{
        .{
            .capability_id = 33,
            .kind = .tool,
            .label = "generated/terminal@v1",
            .ops = &.{
                .{
                    .capability_id = 33,
                    .op_id = 8,
                    .global_op_name = "tool.call",
                    .payload_codec = .unit,
                    .result_codec = .string,
                    .plan_op_ordinal = 0,
                },
            },
        },
        .{
            .capability_id = 20,
            .kind = .tool,
            .label = "generated/primary@v1",
            .ops = &.{
                .{
                    .capability_id = 20,
                    .op_id = 0,
                    .global_op_name = "tool.call",
                    .payload_codec = .unit,
                    .result_codec = .unit,
                    .plan_op_ordinal = 0,
                },
                .{
                    .capability_id = 20,
                    .op_id = 1,
                    .global_op_name = "tool.call",
                    .payload_codec = .unit,
                    .result_codec = .unit,
                    .plan_op_ordinal = 1,
                },
            },
        },
    };

    const bytes = try shift_vm.artifact.encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(bytes);

    var context = string_dispatch_context{};
    var run_result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchTerminalReturn,
    });
    defer run_result.deinit(std.testing.allocator);
    const result = try expectCompleted(&run_result);

    try std.testing.expectEqualStrings("early", result.value.string);
    try std.testing.expectEqual(@as(usize, 1), result.logs.len);
    try conformance.assertToolCallShape(result.logs[0], "generated/terminal@v1", "stop");
}

test "ArtifactV1 runtime decodes terminal abort string results for later requirement ops" {
    const build_fingerprint = shift_vm.artifact.buildFingerprintFromSeed("artifact-runtime-terminal-abort-codec");
    const plan: internal_program_plan.ProgramPlan = .{
        .label = "artifact.runtime.terminal_abort_later_op",
        .ir_hash = 0x92,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 3,
        }},
        .requirements = &.{
            .{ .label = "primary", .first_op = 0, .op_count = 2 },
            .{ .label = "terminal", .first_op = 2, .op_count = 1 },
        },
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "unused-a", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit },
            .{ .requirement_index = 0, .op_name = "unused-b", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit },
            .{ .requirement_index = 1, .op_name = "stop", .mode = .abort, .payload_codec = .unit, .resume_codec = .unit },
        },
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .const_string, .dst = 0, .string_literal = "fallback" },
            .{ .kind = .call_op, .operand = 2 },
            .{ .kind = .return_value, .operand = 0 },
        },
    };
    const capabilities = [_]shift_vm.CapabilityV1{
        .{
            .capability_id = 33,
            .kind = .tool,
            .label = "generated/terminal@v1",
            .ops = &.{
                .{
                    .capability_id = 33,
                    .op_id = 8,
                    .global_op_name = "tool.call",
                    .payload_codec = .unit,
                    .result_codec = .string,
                    .plan_op_ordinal = 0,
                },
            },
        },
        .{
            .capability_id = 20,
            .kind = .tool,
            .label = "generated/primary@v1",
            .ops = &.{
                .{
                    .capability_id = 20,
                    .op_id = 0,
                    .global_op_name = "tool.call",
                    .payload_codec = .unit,
                    .result_codec = .unit,
                    .plan_op_ordinal = 0,
                },
                .{
                    .capability_id = 20,
                    .op_id = 1,
                    .global_op_name = "tool.call",
                    .payload_codec = .unit,
                    .result_codec = .unit,
                    .plan_op_ordinal = 1,
                },
            },
        },
    };

    const bytes = try shift_vm.artifact.encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(bytes);

    var context = string_dispatch_context{};
    var run_result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchTerminalAbort,
    });
    defer run_result.deinit(std.testing.allocator);
    const result = try expectCompleted(&run_result);

    try std.testing.expectEqualStrings("early-abort", result.value.string);
    try std.testing.expectEqual(@as(usize, 1), result.logs.len);
    try conformance.assertToolCallShape(result.logs[0], "generated/terminal@v1", "stop");
}

test "ArtifactV1 runtime rejects host control outcomes incompatible with op mode" {
    const transform_bytes = try encodeSingleStringArtifact(std.testing.allocator, .transform, .string, "artifact-runtime-transform-control-contract");
    defer std.testing.allocator.free(transform_bytes);

    var transform_return_now = FixedControlDispatchContext{ .control = .return_now };
    try std.testing.expectError(error.ProgramContractViolation, shift_vm.runtime.runArtifact(std.testing.allocator, transform_bytes, .{
        .ctx = &transform_return_now,
        .dispatchFn = dispatchFixedControlResult,
    }));

    var transform_abort = FixedControlDispatchContext{ .control = .abort };
    try std.testing.expectError(error.ProgramContractViolation, shift_vm.runtime.runArtifact(std.testing.allocator, transform_bytes, .{
        .ctx = &transform_abort,
        .dispatchFn = dispatchFixedControlResult,
    }));

    const abort_bytes = try encodeSingleStringArtifact(std.testing.allocator, .abort, .unit, "artifact-runtime-abort-control-contract");
    defer std.testing.allocator.free(abort_bytes);

    var abort_resume = FixedControlDispatchContext{
        .control = .@"resume",
        .use_null_value = true,
    };
    try std.testing.expectError(error.ProgramContractViolation, shift_vm.runtime.runArtifact(std.testing.allocator, abort_bytes, .{
        .ctx = &abort_resume,
        .dispatchFn = dispatchFixedControlResult,
    }));
}

test "ArtifactV1 runtime enforces choice control compatibility" {
    const choice_bytes = try encodeSingleStringArtifact(std.testing.allocator, .choice, .string, "artifact-runtime-choice-control-contract");
    defer std.testing.allocator.free(choice_bytes);

    var choice_return_now = FixedControlDispatchContext{
        .control = .return_now,
        .string_value = "choice-early",
    };
    var result = try shift_vm.runtime.runArtifact(std.testing.allocator, choice_bytes, .{
        .ctx = &choice_return_now,
        .dispatchFn = dispatchFixedControlResult,
    });
    defer result.deinit(std.testing.allocator);
    const completed = try expectCompleted(&result);
    try std.testing.expectEqualStrings("choice-early", completed.value.string);

    var choice_abort = FixedControlDispatchContext{ .control = .abort };
    try std.testing.expectError(error.ProgramContractViolation, shift_vm.runtime.runArtifact(std.testing.allocator, choice_bytes, .{
        .ctx = &choice_abort,
        .dispatchFn = dispatchFixedControlResult,
    }));
}

test "ArtifactV1 runtime rejects out-of-range i32 host integers" {
    const bytes = try encodeSingleResumeArtifact(std.testing.allocator, .i32, "artifact-runtime-i32-overflow");
    defer std.testing.allocator.free(bytes);

    var context = IntegerDispatchContext{ .value = std.math.maxInt(i64) };
    try std.testing.expectError(error.ProgramContractViolation, shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchIntegerResult,
    }));
}

test "ArtifactV1 runtime rejects negative usize host integers" {
    const bytes = try encodeSingleResumeArtifact(std.testing.allocator, .usize, "artifact-runtime-usize-overflow");
    defer std.testing.allocator.free(bytes);

    var context = IntegerDispatchContext{ .value = -1 };
    try std.testing.expectError(error.ProgramContractViolation, shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchIntegerResult,
    }));
}

test "ArtifactV1 runtime round-trips usize values above maxInt(i64)" {
    const large_value = @as(u64, std.math.maxInt(i64)) + 1;
    const build_fingerprint = shift_vm.artifact.buildFingerprintFromSeed("artifact-runtime-usize-roundtrip");
    const plan: internal_program_plan.ProgramPlan = .{
        .label = "artifact.runtime.usize_roundtrip",
        .ir_hash = 0xb1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .usize,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 3,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 2 }},
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "load", .mode = .transform, .payload_codec = .unit, .resume_codec = .usize },
            .{ .requirement_index = 0, .op_name = "echo", .mode = .transform, .payload_codec = .usize, .resume_codec = .usize },
        },
        .outputs = &.{},
        .locals = &.{ .{ .codec = .usize }, .{ .codec = .usize } },
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .call_op, .dst = 0, .operand = 0 },
            .{ .kind = .call_op, .dst = 1, .operand = 1, .aux = 0 },
            .{ .kind = .return_value, .operand = 1 },
        },
    };
    const capabilities = [_]shift_vm.CapabilityV1{.{
        .capability_id = 9,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{
            .{
                .capability_id = 9,
                .op_id = 0,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .usize,
                .plan_op_ordinal = 0,
            },
            .{
                .capability_id = 9,
                .op_id = 1,
                .global_op_name = "tool.call",
                .payload_codec = .usize,
                .result_codec = .usize,
                .plan_op_ordinal = 1,
            },
        },
    }};

    const bytes = try shift_vm.artifact.encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(bytes);

    var context = UnsignedIntegerDispatchContext{ .value = large_value };
    var run_result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchUnsignedIntegerRoundTrip,
    });
    defer run_result.deinit(std.testing.allocator);
    const result = try expectCompleted(&run_result);

    try std.testing.expectEqual(@as(?u64, large_value), context.seen_argument);
    try std.testing.expectEqual(@as(usize, @intCast(large_value)), result.value.usize);
    try std.testing.expectEqual(@as(usize, 2), result.logs.len);
    try std.testing.expectEqual(large_value, result.logs[1].request.body.tool_call.arguments.u64);
    try std.testing.expectEqual(large_value, result.logs[1].result.body.success.value.u64);
}

test "ArtifactV1 runtime rejects non-null host values for unit codecs" {
    const bytes = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "artifact-runtime-unit-null-check",
            .capabilities = &.{},
        },
    );
    defer std.testing.allocator.free(bytes);

    var context = RuntimeContext{ .state = 5 };
    defer context.deinit(std.testing.allocator);

    try std.testing.expectError(error.ProgramContractViolation, shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchNonNullUnitResult,
    }));
}

test "ArtifactV1 runtime rejects successful host replies with mismatched tool metadata" {
    const bytes = try encodeSingleResumeArtifact(std.testing.allocator, .i32, "artifact-runtime-mismatched-success");
    defer std.testing.allocator.free(bytes);

    var wrong_tool = IntegerDispatchContext{ .value = 0 };
    try std.testing.expectError(error.ProgramContractViolation, shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &wrong_tool,
        .dispatchFn = dispatchMismatchedSuccess,
    }));

    var wrong_call = IntegerDispatchContext{ .value = 1 };
    try std.testing.expectError(error.ProgramContractViolation, shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &wrong_call,
        .dispatchFn = dispatchMismatchedSuccess,
    }));
}

test "ArtifactV1 runtime rejects host replies with non-v1 schema versions" {
    const bytes = try encodeSingleResumeArtifact(std.testing.allocator, .i32, "artifact-runtime-schema-version");
    defer std.testing.allocator.free(bytes);

    try std.testing.expectError(error.ProgramContractViolation, shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = undefined,
        .dispatchFn = dispatchWrongSchemaVersion,
    }));
}

fn dispatchRejectedFailure(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    _ = ctx;
    return .{
        .request_id = request.request_id,
        .body = .{ .rejected = .{
            .code = try allocator.dupe(u8, "invalid_arguments"),
            .message = try allocator.dupe(u8, "bad payload"),
            .owns_code = true,
            .owns_message = true,
        } },
    };
}

fn dispatchFailedFailure(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    _ = ctx;
    return .{
        .request_id = request.request_id,
        .body = .{ .failed = .{
            .code = try allocator.dupe(u8, "provider_failure"),
            .message = try allocator.dupe(u8, "backend unavailable"),
            .owns_code = true,
            .owns_message = true,
        } },
    };
}

fn dispatchThrownFailure(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    _ = ctx;
    _ = allocator;
    _ = request;
    return error.ProviderBoom;
}

fn dispatchBorrowedFailedFailure(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    _ = ctx;
    _ = allocator;
    return .{
        .request_id = request.request_id,
        .body = .{ .failed = .{
            .code = "provider_failure",
            .message = "backend unavailable",
        } },
    };
}

fn expectRunArtifactLogCleanupOnAllocationFailure(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !void {
    var context = string_dispatch_context{};
    var result = try shift_vm.runtime.runArtifact(allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchBorrowedFailedFailure,
    });
    defer result.deinit(allocator);
}

test "ArtifactV1 runtime surfaces rejected host failures with typed payloads and logs" {
    const bytes = try encodeSingleResumeArtifact(std.testing.allocator, .i32, "artifact-runtime-rejected");
    defer std.testing.allocator.free(bytes);

    var context = string_dispatch_context{};
    var result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchRejectedFailure,
    });
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .rejected => |failure| {
            try std.testing.expectEqualStrings("invalid_arguments", failure.failure.code);
            try std.testing.expectEqualStrings("bad payload", failure.failure.message);
            try std.testing.expectEqual(@as(usize, 1), failure.logs.len);
            try std.testing.expectEqualStrings("generated/tooling@v1", failure.logs[0].request.body.tool_call.tool_id);
            try std.testing.expectEqualStrings("value", failure.logs[0].request.body.tool_call.op_name);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ArtifactV1 runtime surfaces failed host failures with typed payloads and logs" {
    const bytes = try encodeSingleResumeArtifact(std.testing.allocator, .i32, "artifact-runtime-failed");
    defer std.testing.allocator.free(bytes);

    var context = string_dispatch_context{};
    var result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchFailedFailure,
    });
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .failed => |failure| {
            try std.testing.expectEqualStrings("provider_failure", failure.failure.code);
            try std.testing.expectEqualStrings("backend unavailable", failure.failure.message);
            try std.testing.expectEqual(@as(usize, 1), failure.logs.len);
            try std.testing.expectEqualStrings("generated/tooling@v1", failure.logs[0].request.body.tool_call.tool_id);
            try std.testing.expectEqualStrings("value", failure.logs[0].request.body.tool_call.op_name);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ArtifactV1 runtime maps thrown host dispatch errors to typed provider failures" {
    const bytes = try encodeSingleResumeArtifact(std.testing.allocator, .i32, "artifact-runtime-dispatch-throw");
    defer std.testing.allocator.free(bytes);

    var context = string_dispatch_context{};
    var result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchThrownFailure,
    });
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .failed => |failure| {
            try std.testing.expectEqualStrings("provider_failure", failure.failure.code);
            try std.testing.expectEqualStrings("ProviderBoom", failure.failure.message);
            try std.testing.expectEqual(@as(usize, 1), failure.logs.len);
            try std.testing.expectEqualStrings("generated/tooling@v1", failure.logs[0].request.body.tool_call.tool_id);
            try std.testing.expectEqualStrings("value", failure.logs[0].request.body.tool_call.op_name);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ArtifactV1 runtime unwinds cloned transcript entries when logging hits allocator failure" {
    const bytes = try encodeSingleResumeArtifact(std.testing.allocator, .i32, "artifact-runtime-log-cleanup");
    defer std.testing.allocator.free(bytes);

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        expectRunArtifactLogCleanupOnAllocationFailure,
        .{bytes},
    );
}
