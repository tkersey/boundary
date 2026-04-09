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
            } },
        };
    }
    return .{
        .request_id = request.request_id,
        .body = .{ .failed = .{
            .code = try allocator.dupe(u8, "unknown_op"),
            .message = try allocator.dupe(u8, tool_call.op_name),
        } },
    };
}

const string_dispatch_context = struct {};

fn dispatchStringResults(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    request: shift_vm.host_adapter.HostEffectRequestV1,
) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    _ = ctx;
    try std.testing.expectEqual(@as(u16, 7), request.capability_id);
    try std.testing.expectEqualStrings("generated/tooling@v1", request.body.tool_call.tool_id);
    const value = switch (request.op_id) {
        3 => "keepalive0",
        4 => "overwrite0",
        else => return error.UnexpectedOpId,
    };
    return .{
        .request_id = request.request_id,
        .body = .{ .success = .{
            .tool_id = try allocator.dupe(u8, request.body.tool_call.tool_id),
            .call_id = request.body.tool_call.call_id,
            .control = .@"resume",
            .value = .{ .string = try allocator.dupe(u8, value) },
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
        } },
    };
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

    var result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatch,
    });
    defer result.deinit(std.testing.allocator);

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

    var artifact_result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatch,
    });
    defer artifact_result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings(lowered_result.value, artifact_result.value.string);
    try std.testing.expectEqual(lowered_result.outputs.state, context.state);
    try std.testing.expectEqual(lowered_result.outputs.writer.len, context.writer_items.items.len);
    for (lowered_result.outputs.writer, context.writer_items.items) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
    }
}

test "ArtifactV1 runtime uses manifest capability ids and keeps resumed strings alive" {
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
                .op_id = 3,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .string,
            },
            .{
                .capability_id = 7,
                .op_id = 4,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .string,
            },
        },
    }};

    const bytes = try shift_vm.artifact.encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(bytes);

    var context = string_dispatch_context{};
    var result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchStringResults,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("keepalive0", result.value.string);
    try std.testing.expectEqual(@as(usize, 2), result.logs.len);
    try std.testing.expectEqual(@as(u16, 7), result.logs[0].request.capability_id);
    try std.testing.expectEqual(@as(u16, 3), result.logs[0].request.op_id);
    try std.testing.expectEqual(@as(u16, 4), result.logs[1].request.op_id);
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
                },
                .{
                    .capability_id = 20,
                    .op_id = 1,
                    .global_op_name = "tool.call",
                    .payload_codec = .unit,
                    .result_codec = .unit,
                },
            },
        },
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
    var result = try shift_vm.runtime.runArtifact(std.testing.allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatchTerminalReturn,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("early", result.value.string);
    try std.testing.expectEqual(@as(usize, 1), result.logs.len);
    try conformance.assertToolCallShape(result.logs[0], "generated/terminal@v1", "stop");
}
