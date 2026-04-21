const host_api = @import("host_adapter_v1");
const runtime_api = @import("artifact_vm_runtime");
const std = @import("std");

/// Supported host boundary for agent-vm execution.
pub const host = struct {
    /// Typed recursive payload tree accepted by the supported host boundary.
    pub const DataValue = host_api.DataValueV1;
    /// Ownership mode for public host payload values.
    pub const DataValueOwnership = host_api.DataValueOwnershipV1;
    /// Typed failure payload surfaced by the supported host boundary.
    pub const Failure = host_api.FailureV1;
    /// One object field nested inside `DataValue.object`.
    pub const ObjectField = host_api.ObjectFieldV1;
    /// Declared runtime output codecs.
    pub const OutputCodec = host_api.OutputCodecV1;
    /// One declared runtime output descriptor.
    pub const OutputDescriptor = host_api.OutputDescriptorV1;

    /// One host call request for a normal operation dispatch.
    pub const CallRequest = struct {
        request_id: u64,
        capability_id: u16,
        op_id: u16,
        tool_id: []const u8,
        op_name: []const u8,
        arguments: DataValue,
        owns_tool_id: bool = false,
        owns_op_name: bool = false,
        arguments_ownership: DataValueOwnership = .borrowed,

        /// Release allocator-owned request storage.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.owns_tool_id) allocator.free(self.tool_id);
            if (self.owns_op_name) allocator.free(self.op_name);
            self.arguments.deinitWithOwnership(allocator, self.arguments_ownership);
            self.* = undefined;
        }
    };

    /// One host request for an after-call replay step.
    pub const AfterCallRequest = struct {
        request_id: u64,
        capability_id: u16,
        op_id: u16,
        tool_id: []const u8,
        op_name: []const u8,
        call_id: u64,
        answer: DataValue,
        owns_tool_id: bool = false,
        owns_op_name: bool = false,
        answer_ownership: DataValueOwnership = .borrowed,

        /// Release allocator-owned request storage.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.owns_tool_id) allocator.free(self.tool_id);
            if (self.owns_op_name) allocator.free(self.op_name);
            self.answer.deinitWithOwnership(allocator, self.answer_ownership);
            self.* = undefined;
        }
    };

    /// Structural host request variants exposed by the supported boundary.
    pub const Request = union(enum) {
        after_call: AfterCallRequest,
        call: CallRequest,

        /// Release allocator-owned request storage.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            switch (self.*) {
                .after_call => |*value| value.deinit(allocator),
                .call => |*value| value.deinit(allocator),
            }
            self.* = undefined;
        }
    };

    /// Resumptive host response carrying a resumed value.
    pub const Resumed = struct {
        request_id: u64,
        tool_id: []const u8,
        call_id: u64,
        value: DataValue,
        owns_tool_id: bool = false,
        value_ownership: DataValueOwnership = .borrowed,

        /// Release allocator-owned response storage.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.owns_tool_id) allocator.free(self.tool_id);
            self.value.deinitWithOwnership(allocator, self.value_ownership);
            self.* = undefined;
        }
    };

    /// Terminal host response carrying an immediate answer.
    pub const Terminal = struct {
        request_id: u64,
        tool_id: []const u8,
        call_id: u64,
        value: DataValue,
        owns_tool_id: bool = false,
        value_ownership: DataValueOwnership = .borrowed,

        /// Release allocator-owned response storage.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.owns_tool_id) allocator.free(self.tool_id);
            self.value.deinitWithOwnership(allocator, self.value_ownership);
            self.* = undefined;
        }
    };

    /// Structural host response variants exposed by the supported boundary.
    pub const Response = union(enum) {
        aborted: Terminal,
        failed: Failure,
        rejected: Failure,
        resumed: Resumed,
        return_now: Terminal,

        /// Release allocator-owned response storage.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            switch (self.*) {
                .aborted => |*value| value.deinit(allocator),
                .failed => |*value| value.deinit(allocator),
                .rejected => |*value| value.deinit(allocator),
                .resumed => |*value| value.deinit(allocator),
                .return_now => |*value| value.deinit(allocator),
            }
            self.* = undefined;
        }
    };

    /// Logged request/response pair captured during runtime execution.
    pub const LogEntry = struct {
        request: Request,
        response: Response,

        /// Release allocator-owned request and response storage.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.request.deinit(allocator);
            self.response.deinit(allocator);
            self.* = undefined;
        }
    };

    /// Supported synchronous adapter surface for artifact execution.
    pub const Adapter = struct {
        ctx: ?*anyopaque,
        dispatchFn: *const fn (ctx: ?*anyopaque, allocator: std.mem.Allocator, request: Request) anyerror!Response,
        collectOutputsFn: ?*const fn (ctx: ?*anyopaque, allocator: std.mem.Allocator, declared_outputs: []const OutputDescriptor) anyerror![]DataValue = null,

        /// Dispatch one structural host request.
        pub fn dispatch(self: @This(), allocator: std.mem.Allocator, request: Request) anyerror!Response {
            return self.dispatchFn(self.ctx, allocator, request);
        }

        /// Collect the declared output bundle after root completion.
        pub fn collectOutputs(
            self: @This(),
            allocator: std.mem.Allocator,
            declared_outputs: []const OutputDescriptor,
        ) anyerror![]DataValue {
            if (declared_outputs.len == 0) return allocator.alloc(DataValue, 0);
            const collect = self.collectOutputsFn orelse return error.MissingOutputSnapshot;
            return collect(self.ctx, allocator, declared_outputs);
        }
    };
};

/// Supported synchronous runtime surface for agent-vm execution.
pub const runtime = struct {
    /// One finalized runtime output value.
    pub const ExecutionOutput = struct {
        label: []u8,
        codec: host.OutputCodec,
        value: host.DataValue,

        /// Release the owned output label and value payload.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.label);
            self.value.deinit(allocator);
            self.* = undefined;
        }
    };
    /// One successful artifact execution result.
    pub const ExecutionResult = struct {
        value: host.DataValue,
        outputs: []ExecutionOutput,
        logs: []host.LogEntry,

        /// Release the owned runtime value, captured outputs, and public host logs.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.value.deinit(allocator);
            deinitExecutionOutputs(allocator, self.outputs);
            deinitHostLogs(allocator, self.logs);
            self.* = .{
                .value = .null,
                .outputs = &.{},
                .logs = &.{},
            };
        }
    };
    /// One host failure plus captured logs.
    pub const HostFailureResult = struct {
        failure: host.Failure,
        logs: []host.LogEntry,

        /// Release the owned host failure payload and captured public host logs.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.failure.deinit(allocator);
            deinitHostLogs(allocator, self.logs);
            self.* = undefined;
        }
    };
    /// Result of executing artifact bytes through the supported runtime surface.
    pub const RunArtifactResult = union(enum) {
        completed: ExecutionResult,
        failed: HostFailureResult,
        rejected: HostFailureResult,

        /// Release the owned execution or host-failure result.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            switch (self.*) {
                .completed => |*result| result.deinit(allocator),
                .failed => |*failure| failure.deinit(allocator),
                .rejected => |*failure| failure.deinit(allocator),
            }
            self.* = undefined;
        }
    };

    /// Execute artifact bytes through the supported agent-vm runtime surface.
    pub fn runArtifact(
        allocator: std.mem.Allocator,
        bytes: []const u8,
        adapter: host.Adapter,
    ) anyerror!RunArtifactResult {
        var bridge_adapter = adapter;
        var internal_result = try runtime_api.runArtifact(allocator, bytes, .{
            .ctx = &bridge_adapter,
            .dispatchFn = bridgeDispatch,
            .collectOutputsFn = bridgeCollectOutputs,
        });
        defer internal_result.deinit(allocator);
        return try runArtifactResultFromInternal(allocator, internal_result);
    }
};

fn bridgeDispatch(
    ctx_ptr: ?*anyopaque,
    allocator: std.mem.Allocator,
    request: host_api.HostEffectRequestV1,
) anyerror!host_api.HostEffectResultV1 {
    const adapter: *host.Adapter = @ptrCast(@alignCast(ctx_ptr.?));
    var public_request = try requestFromInternal(allocator, request);
    defer public_request.deinit(allocator);

    var public_response = try adapter.dispatch(allocator, public_request);
    defer public_response.deinit(allocator);

    return try responseToInternal(allocator, request.request_id, public_response);
}

fn bridgeCollectOutputs(
    ctx_ptr: ?*anyopaque,
    allocator: std.mem.Allocator,
    declared_outputs: []const host_api.OutputDescriptorV1,
) anyerror![]host_api.DataValueV1 {
    const adapter: *host.Adapter = @ptrCast(@alignCast(ctx_ptr.?));
    return try adapter.collectOutputs(allocator, declared_outputs);
}

fn runArtifactResultFromInternal(
    allocator: std.mem.Allocator,
    result: runtime_api.RunArtifactResultV1,
) !runtime.RunArtifactResult {
    return switch (result) {
        .completed => |completed| .{ .completed = try executionResultFromInternal(allocator, completed) },
        .failed => |failure| .{ .failed = try hostFailureResultFromInternal(allocator, failure) },
        .rejected => |failure| .{ .rejected = try hostFailureResultFromInternal(allocator, failure) },
    };
}

fn executionResultFromInternal(
    allocator: std.mem.Allocator,
    result: runtime_api.ExecutionResultV1,
) !runtime.ExecutionResult {
    var value = try dataValueFromProgramValue(allocator, result.value);
    errdefer value.deinit(allocator);
    const outputs = try executionOutputsFromInternal(allocator, result.outputs);
    errdefer deinitExecutionOutputs(allocator, outputs);
    const logs = try hostLogsFromInternal(allocator, result.logs);
    errdefer deinitHostLogs(allocator, logs);
    return .{
        .value = value,
        .outputs = outputs,
        .logs = logs,
    };
}

fn hostFailureResultFromInternal(
    allocator: std.mem.Allocator,
    result: runtime_api.HostFailureResultV1,
) !runtime.HostFailureResult {
    var failure = try result.failure.clone(allocator);
    errdefer failure.deinit(allocator);
    const logs = try hostLogsFromInternal(allocator, result.logs);
    errdefer deinitHostLogs(allocator, logs);
    return .{
        .failure = failure,
        .logs = logs,
    };
}

fn executionOutputsFromInternal(
    allocator: std.mem.Allocator,
    outputs: []const runtime_api.ExecutionOutputV1,
) ![]runtime.ExecutionOutput {
    const owned_outputs = try allocator.alloc(runtime.ExecutionOutput, outputs.len);
    var initialized: usize = 0;
    errdefer deinitExecutionOutputsPrefix(allocator, owned_outputs, initialized);
    for (outputs, 0..) |output, index| {
        const label = try allocator.dupe(u8, output.label);
        errdefer allocator.free(label);
        const value = try output.value.clone(allocator);
        errdefer {
            var owned_value = value;
            owned_value.deinit(allocator);
        }
        owned_outputs[index] = .{
            .label = label,
            .codec = output.codec,
            .value = value,
        };
        initialized += 1;
    }
    return owned_outputs;
}

fn hostLogsFromInternal(
    allocator: std.mem.Allocator,
    logs: []const host_api.HostLogEntryV1,
) ![]host.LogEntry {
    const owned_logs = try allocator.alloc(host.LogEntry, logs.len);
    var initialized: usize = 0;
    errdefer deinitHostLogsPrefix(allocator, owned_logs, initialized);
    for (logs, 0..) |entry, index| {
        owned_logs[index] = try hostLogFromInternal(allocator, entry);
        initialized += 1;
    }
    return owned_logs;
}

fn hostLogFromInternal(
    allocator: std.mem.Allocator,
    entry: host_api.HostLogEntryV1,
) !host.LogEntry {
    var request = try requestFromInternal(allocator, entry.request);
    errdefer request.deinit(allocator);
    var response = try responseFromInternal(allocator, entry.result);
    errdefer response.deinit(allocator);
    return .{
        .request = request,
        .response = response,
    };
}

fn requestFromInternal(allocator: std.mem.Allocator, request: host_api.HostEffectRequestV1) !host.Request {
    const tool_call = request.body.tool_call;
    const tool_id = try allocator.dupe(u8, tool_call.tool_id);
    errdefer allocator.free(tool_id);
    const op_name = try allocator.dupe(u8, tool_call.op_name);
    errdefer allocator.free(op_name);
    const payload = try tool_call.arguments.clone(allocator);
    errdefer {
        var owned_payload = payload;
        owned_payload.deinit(allocator);
    }

    if (tool_call.call_id == request.request_id) {
        return .{ .call = .{
            .request_id = request.request_id,
            .capability_id = request.capability_id,
            .op_id = request.op_id,
            .tool_id = tool_id,
            .op_name = op_name,
            .arguments = payload,
            .owns_tool_id = true,
            .owns_op_name = true,
            .arguments_ownership = .deep,
        } };
    }

    return .{ .after_call = .{
        .request_id = request.request_id,
        .capability_id = request.capability_id,
        .op_id = request.op_id,
        .tool_id = tool_id,
        .op_name = op_name,
        .call_id = tool_call.call_id,
        .answer = payload,
        .owns_tool_id = true,
        .owns_op_name = true,
        .answer_ownership = .deep,
    } };
}

fn responseFromInternal(
    allocator: std.mem.Allocator,
    response: host_api.HostEffectResultV1,
) !host.Response {
    return switch (response.body) {
        .success => |value| switch (value.control) {
            .@"resume" => .{ .resumed = try cloneResumedResponse(allocator, response.request_id, value) },
            .return_now => .{ .return_now = try cloneTerminalResponse(allocator, response.request_id, value) },
            .abort => .{ .aborted = try cloneTerminalResponse(allocator, response.request_id, value) },
        },
        .rejected => |value| .{ .rejected = try value.clone(allocator) },
        .failed => |value| .{ .failed = try value.clone(allocator) },
    };
}

fn cloneResumedResponse(
    allocator: std.mem.Allocator,
    request_id: u64,
    value: host_api.ToolCallResultV1,
) !host.Resumed {
    const tool_id = try allocator.dupe(u8, value.tool_id);
    errdefer allocator.free(tool_id);
    const cloned_value = try value.value.clone(allocator);
    errdefer {
        var owned_value = cloned_value;
        owned_value.deinit(allocator);
    }
    return .{
        .request_id = request_id,
        .tool_id = tool_id,
        .call_id = value.call_id,
        .value = cloned_value,
        .owns_tool_id = true,
        .value_ownership = .deep,
    };
}

fn cloneTerminalResponse(
    allocator: std.mem.Allocator,
    request_id: u64,
    value: host_api.ToolCallResultV1,
) !host.Terminal {
    const tool_id = try allocator.dupe(u8, value.tool_id);
    errdefer allocator.free(tool_id);
    const cloned_value = try value.value.clone(allocator);
    errdefer {
        var owned_value = cloned_value;
        owned_value.deinit(allocator);
    }
    return .{
        .request_id = request_id,
        .tool_id = tool_id,
        .call_id = value.call_id,
        .value = cloned_value,
        .owns_tool_id = true,
        .value_ownership = .deep,
    };
}

fn responseToInternal(
    allocator: std.mem.Allocator,
    request_id: u64,
    response: host.Response,
) !host_api.HostEffectResultV1 {
    return switch (response) {
        .resumed => |value| try cloneSuccessResult(allocator, request_id, .@"resume", value),
        .return_now => |value| try cloneSuccessResult(allocator, request_id, .return_now, value),
        .aborted => |value| try cloneSuccessResult(allocator, request_id, .abort, value),
        .rejected => |value| .{
            .request_id = request_id,
            .body = .{ .rejected = try value.clone(allocator) },
        },
        .failed => |value| .{
            .request_id = request_id,
            .body = .{ .failed = try value.clone(allocator) },
        },
    };
}

fn cloneSuccessResult(
    allocator: std.mem.Allocator,
    request_id: u64,
    control: host_api.ToolControlV1,
    value: anytype,
) !host_api.HostEffectResultV1 {
    if (value.request_id != request_id) {
        return invalidHostReplyResult(allocator, request_id, "host reply request_id must echo the request");
    }
    const tool_id = try allocator.dupe(u8, value.tool_id);
    errdefer allocator.free(tool_id);
    const cloned_value = try value.value.clone(allocator);
    errdefer {
        var owned_value = cloned_value;
        owned_value.deinit(allocator);
    }
    return .{
        .request_id = request_id,
        .body = .{ .success = .{
            .tool_id = tool_id,
            .call_id = value.call_id,
            .control = control,
            .value = cloned_value,
            .owns_tool_id = true,
            .value_ownership = .deep,
        } },
    };
}

fn invalidHostReplyResult(
    allocator: std.mem.Allocator,
    request_id: u64,
    message: []const u8,
) !host_api.HostEffectResultV1 {
    const code = try allocator.dupe(u8, "invalid_host_reply");
    errdefer allocator.free(code);
    const owned_message = try allocator.dupe(u8, message);
    return .{
        .request_id = request_id,
        .body = .{ .failed = .{
            .code = code,
            .message = owned_message,
            .owns_code = true,
            .owns_message = true,
        } },
    };
}

fn dataValueFromProgramValue(allocator: std.mem.Allocator, value: anytype) !host.DataValue {
    return switch (value) {
        .none => .null,
        .bool => |typed| .{ .bool = typed },
        .i32 => |typed| .{ .i64 = typed },
        .usize => |typed| .{ .u64 = typed },
        .string => |typed| .{ .string = try allocator.dupe(u8, typed) },
    };
}

fn deinitExecutionOutputs(allocator: std.mem.Allocator, outputs: []runtime.ExecutionOutput) void {
    for (outputs) |*output| output.deinit(allocator);
    allocator.free(outputs);
}

fn deinitExecutionOutputsPrefix(
    allocator: std.mem.Allocator,
    outputs: []runtime.ExecutionOutput,
    initialized: usize,
) void {
    for (outputs[0..initialized]) |*output| output.deinit(allocator);
    allocator.free(outputs);
}

fn deinitHostLogs(allocator: std.mem.Allocator, logs: []host.LogEntry) void {
    for (logs) |*entry| entry.deinit(allocator);
    allocator.free(logs);
}

fn deinitHostLogsPrefix(
    allocator: std.mem.Allocator,
    logs: []host.LogEntry,
    initialized: usize,
) void {
    for (logs[0..initialized]) |*entry| entry.deinit(allocator);
    allocator.free(logs);
}

test {
    _ = host.Adapter;
    _ = host.CallRequest;
    _ = host.AfterCallRequest;
    _ = host.Request;
    _ = host.Response;
    _ = runtime.ExecutionOutput;
    _ = runtime.ExecutionResult;
    _ = runtime.RunArtifactResult;
    _ = runtime.runArtifact;
}

test "request bridge classifies non-root call ids as after_call" {
    const request: host_api.HostEffectRequestV1 = .{
        .request_id = 22,
        .capability_id = 3,
        .op_id = 7,
        .body = .{ .tool_call = .{
            .tool_id = "generated/tooling@v1",
            .call_id = 11,
            .op_name = "afterTell",
            .arguments = .{ .string = "wrapped" },
        } },
    };

    var bridged = try requestFromInternal(std.testing.allocator, request);
    defer bridged.deinit(std.testing.allocator);

    switch (bridged) {
        .after_call => |after_call| {
            try std.testing.expectEqual(@as(u64, 22), after_call.request_id);
            try std.testing.expectEqual(@as(u64, 11), after_call.call_id);
            try std.testing.expectEqualStrings("afterTell", after_call.op_name);
            switch (after_call.answer) {
                .string => |value| try std.testing.expectEqualStrings("wrapped", value),
                else => return error.TestUnexpectedPayload,
            }
        },
        else => return error.TestUnexpectedRequestKind,
    }
}

test "response bridge preserves request ids for failed responses" {
    var response: host.Response = .{ .failed = .{
        .code = "provider_failure",
        .message = "boom",
    } };
    defer response.deinit(std.testing.allocator);

    var bridged = try responseToInternal(std.testing.allocator, 41, response);
    defer bridged.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u64, 41), bridged.request_id);
    switch (bridged.body) {
        .failed => |failure| {
            try std.testing.expectEqualStrings("provider_failure", failure.code);
            try std.testing.expectEqualStrings("boom", failure.message);
        },
        else => return error.TestUnexpectedResponseKind,
    }
}

fn expectResponseBridgeSuccessRequiresMatchingRequestId(kind: enum { aborted, resumed, return_now }) !void {
    const request_id: u64 = 41;
    var response: host.Response = switch (kind) {
        .resumed => .{ .resumed = .{
            .request_id = request_id,
            .tool_id = "generated/tooling@v1",
            .call_id = 7,
            .value = .{ .string = "value" },
        } },
        .return_now => .{ .return_now = .{
            .request_id = request_id,
            .tool_id = "generated/tooling@v1",
            .call_id = 7,
            .value = .{ .string = "value" },
        } },
        .aborted => .{ .aborted = .{
            .request_id = request_id,
            .tool_id = "generated/tooling@v1",
            .call_id = 7,
            .value = .{ .string = "value" },
        } },
    };
    defer response.deinit(std.testing.allocator);

    var bridged = try responseToInternal(std.testing.allocator, request_id, response);
    defer bridged.deinit(std.testing.allocator);

    try std.testing.expectEqual(request_id, bridged.request_id);
    switch (bridged.body) {
        .success => |success| {
            const expected_control: host_api.ToolControlV1 = switch (kind) {
                .resumed => .@"resume",
                .return_now => .return_now,
                .aborted => .abort,
            };
            try std.testing.expectEqual(expected_control, success.control);
            try std.testing.expectEqualStrings("generated/tooling@v1", success.tool_id);
            switch (success.value) {
                .string => |string_value| try std.testing.expectEqualStrings("value", string_value),
                else => return error.TestUnexpectedPayload,
            }
        },
        else => return error.TestUnexpectedResponseKind,
    }
}

test "response bridge preserves matching request ids for success responses" {
    try expectResponseBridgeSuccessRequiresMatchingRequestId(.resumed);
    try expectResponseBridgeSuccessRequiresMatchingRequestId(.return_now);
    try expectResponseBridgeSuccessRequiresMatchingRequestId(.aborted);
}

fn expectResponseBridgeRejectsMismatchedSuccessRequestId(kind: enum { aborted, resumed, return_now }) !void {
    const outer_request_id: u64 = 41;
    const responder_request_id: u64 = 99;
    var response: host.Response = switch (kind) {
        .resumed => .{ .resumed = .{
            .request_id = responder_request_id,
            .tool_id = "generated/tooling@v1",
            .call_id = 7,
            .value = .{ .string = "value" },
        } },
        .return_now => .{ .return_now = .{
            .request_id = responder_request_id,
            .tool_id = "generated/tooling@v1",
            .call_id = 7,
            .value = .{ .string = "value" },
        } },
        .aborted => .{ .aborted = .{
            .request_id = responder_request_id,
            .tool_id = "generated/tooling@v1",
            .call_id = 7,
            .value = .{ .string = "value" },
        } },
    };
    defer response.deinit(std.testing.allocator);

    var bridged = try responseToInternal(std.testing.allocator, outer_request_id, response);
    defer bridged.deinit(std.testing.allocator);

    try std.testing.expectEqual(outer_request_id, bridged.request_id);
    switch (bridged.body) {
        .failed => |failure| {
            try std.testing.expectEqualStrings("invalid_host_reply", failure.code);
            try std.testing.expectEqualStrings("host reply request_id must echo the request", failure.message);
        },
        else => return error.TestUnexpectedResponseKind,
    }
}

test "response bridge rejects mismatched request ids for success responses" {
    try expectResponseBridgeRejectsMismatchedSuccessRequestId(.resumed);
    try expectResponseBridgeRejectsMismatchedSuccessRequestId(.return_now);
    try expectResponseBridgeRejectsMismatchedSuccessRequestId(.aborted);
}

fn expectResponseBridgeClonesToolIdWithoutLeaksOnAllocationFailure(allocator: std.mem.Allocator) !void {
    var response: host.Response = .{ .resumed = .{
        .request_id = 41,
        .tool_id = "generated/tooling@v1",
        .call_id = 7,
        .value = .{ .string = "value" },
    } };
    defer response.deinit(std.testing.allocator);

    var bridged = try responseToInternal(allocator, 41, response);
    defer bridged.deinit(allocator);

    try std.testing.expectEqual(@as(u64, 41), bridged.request_id);
    switch (bridged.body) {
        .success => |success| {
            try std.testing.expectEqual(.@"resume", success.control);
            try std.testing.expectEqualStrings("generated/tooling@v1", success.tool_id);
            switch (success.value) {
                .string => |string_value| try std.testing.expectEqualStrings("value", string_value),
                else => return error.TestUnexpectedPayload,
            }
        },
        else => return error.TestUnexpectedResponseKind,
    }
}

test "response bridge frees duplicated tool ids on allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        expectResponseBridgeClonesToolIdWithoutLeaksOnAllocationFailure,
        .{},
    );
}

fn expectExecutionOutputsFromInternalCleansUpPartialAllocations(allocator: std.mem.Allocator) !void {
    const outputs = [_]runtime_api.ExecutionOutputV1{
        .{
            .label = @constCast("answer"),
            .codec = .string,
            .value = .{ .string = "value" },
        },
    };

    const owned_outputs = try executionOutputsFromInternal(allocator, &outputs);
    defer deinitExecutionOutputs(allocator, owned_outputs);

    try std.testing.expectEqual(@as(usize, 1), owned_outputs.len);
    try std.testing.expectEqualStrings("answer", owned_outputs[0].label);
    switch (owned_outputs[0].value) {
        .string => |value| try std.testing.expectEqualStrings("value", value),
        else => return error.TestUnexpectedPayload,
    }
}

test "execution output bridge frees duplicated labels on allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        expectExecutionOutputsFromInternalCleansUpPartialAllocations,
        .{},
    );
}

fn expectResponseFromInternalCleansUpDuplicatedToolIds(allocator: std.mem.Allocator) !void {
    const response: host_api.HostEffectResultV1 = .{
        .request_id = 41,
        .body = .{ .success = .{
            .tool_id = "generated/tooling@v1",
            .call_id = 7,
            .control = .@"resume",
            .value = .{ .string = "value" },
        } },
    };

    var bridged = try responseFromInternal(allocator, response);
    defer bridged.deinit(allocator);

    switch (bridged) {
        .resumed => |resumed| {
            try std.testing.expectEqual(@as(u64, 41), resumed.request_id);
            try std.testing.expectEqualStrings("generated/tooling@v1", resumed.tool_id);
            switch (resumed.value) {
                .string => |value| try std.testing.expectEqualStrings("value", value),
                else => return error.TestUnexpectedPayload,
            }
        },
        else => return error.TestUnexpectedResponseKind,
    }
}

test "response bridge frees duplicated tool ids when public response cloning fails" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        expectResponseFromInternalCleansUpDuplicatedToolIds,
        .{},
    );
}
