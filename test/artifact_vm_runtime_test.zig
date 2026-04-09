const conformance = @import("host_adapter_v1_conformance");
const example = @import("example_open_row_state_writer");
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
