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
    /// Logged request/result pair captured during runtime execution.
    pub const LogEntry = host_api.HostLogEntryV1;
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
    pub const ExecutionOutput = runtime_api.ExecutionOutputV1;
    /// One successful artifact execution result.
    pub const ExecutionResult = runtime_api.ExecutionResultV1;
    /// One host failure plus captured logs.
    pub const HostFailureResult = runtime_api.HostFailureResultV1;
    /// Result of executing artifact bytes through the supported runtime surface.
    pub const RunArtifactResult = runtime_api.RunArtifactResultV1;

    /// Execute artifact bytes through the supported agent-vm runtime surface.
    pub fn runArtifact(
        allocator: std.mem.Allocator,
        bytes: []const u8,
        adapter: host.Adapter,
    ) anyerror!RunArtifactResult {
        var bridge_adapter = adapter;
        return runtime_api.runArtifact(allocator, bytes, .{
            .ctx = &bridge_adapter,
            .dispatchFn = bridgeDispatch,
            .collectOutputsFn = bridgeCollectOutputs,
        });
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

fn responseToInternal(
    allocator: std.mem.Allocator,
    request_id: u64,
    response: host.Response,
) !host_api.HostEffectResultV1 {
    return switch (response) {
        .resumed => |value| .{
            .request_id = value.request_id,
            .body = .{ .success = .{
                .tool_id = try allocator.dupe(u8, value.tool_id),
                .call_id = value.call_id,
                .control = .@"resume",
                .value = try value.value.clone(allocator),
                .owns_tool_id = true,
                .value_ownership = .deep,
            } },
        },
        .return_now => |value| .{
            .request_id = value.request_id,
            .body = .{ .success = .{
                .tool_id = try allocator.dupe(u8, value.tool_id),
                .call_id = value.call_id,
                .control = .return_now,
                .value = try value.value.clone(allocator),
                .owns_tool_id = true,
                .value_ownership = .deep,
            } },
        },
        .aborted => |value| .{
            .request_id = value.request_id,
            .body = .{ .success = .{
                .tool_id = try allocator.dupe(u8, value.tool_id),
                .call_id = value.call_id,
                .control = .abort,
                .value = try value.value.clone(allocator),
                .owns_tool_id = true,
                .value_ownership = .deep,
            } },
        },
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
