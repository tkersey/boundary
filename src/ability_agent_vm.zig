const host_api = @import("./host_adapter_v1.zig");
const runtime_api = @import("./artifact_vm_runtime.zig");
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

    /// One completed output snapshot with explicit payload ownership.
    pub const OutputSnapshot = struct {
        /// Optional declared-output label echoed by the adapter.
        /// Multi-output snapshots must carry the matching label so same-codec
        /// values cannot be silently associated with the wrong output.
        label: ?[]const u8 = null,
        value: DataValue,
        value_ownership: DataValueOwnership = .borrowed,

        /// Release allocator-owned output snapshot storage.
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.value.deinitWithOwnership(allocator, self.value_ownership);
            self.* = undefined;
        }
    };

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
        collectOutputSnapshotsFn: ?*const fn (ctx: ?*anyopaque, allocator: std.mem.Allocator, declared_outputs: []const OutputDescriptor) anyerror![]OutputSnapshot = null,
        /// Legacy completion hook for declared ArtifactV1 entry outputs.
        /// Returned values must be allocator-owned and match the declared outputs exactly.
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

        /// Collect the declared output bundle with explicit value ownership.
        pub fn collectOutputSnapshots(
            self: @This(),
            allocator: std.mem.Allocator,
            declared_outputs: []const OutputDescriptor,
        ) anyerror![]OutputSnapshot {
            if (declared_outputs.len == 0) return allocator.alloc(OutputSnapshot, 0);
            if (self.collectOutputSnapshotsFn) |collect_snapshots| {
                const snapshots = try collect_snapshots(self.ctx, allocator, declared_outputs);
                validateOutputSnapshotLabels(declared_outputs, snapshots, .require_explicit_multi_output) catch |err| {
                    deinitOutputSnapshots(allocator, snapshots);
                    return err;
                };
                return snapshots;
            }

            const collect = self.collectOutputsFn orelse return error.MissingOutputSnapshot;
            var values = try collect(self.ctx, allocator, declared_outputs);
            defer allocator.free(values);
            errdefer for (values) |*value| value.deinit(allocator);
            if (values.len != declared_outputs.len) return error.OutputSnapshotCountMismatch;

            const snapshots = try allocator.alloc(OutputSnapshot, values.len);
            var initialized: usize = 0;
            errdefer {
                for (snapshots[0..initialized]) |*snapshot| snapshot.deinit(allocator);
                allocator.free(snapshots);
            }

            for (values, 0..) |value, index| {
                snapshots[index] = .{
                    .label = declared_outputs[index].label,
                    .value = value,
                    .value_ownership = .deep,
                };
                values[index] = .null;
                initialized += 1;
            }
            return snapshots;
        }
    };
};

fn deinitOutputSnapshots(allocator: std.mem.Allocator, snapshots: []host.OutputSnapshot) void {
    for (snapshots) |*snapshot| snapshot.deinit(allocator);
    allocator.free(snapshots);
}

const SnapshotLabelPolicy = enum {
    allow_positional_single_output,
    require_explicit_multi_output,
};

fn validateOutputSnapshotLabels(
    declared_outputs: []const host_api.OutputDescriptorV1,
    snapshots: []const host.OutputSnapshot,
    label_policy: SnapshotLabelPolicy,
) !void {
    if (snapshots.len != declared_outputs.len) return error.OutputSnapshotCountMismatch;

    const require_labels = switch (label_policy) {
        .allow_positional_single_output => false,
        .require_explicit_multi_output => declared_outputs.len > 1,
    };
    for (snapshots, 0..) |snapshot, index| {
        if (snapshot.label) |label| {
            if (!std.mem.eql(u8, label, declared_outputs[index].label)) return error.OutputSnapshotLabelMismatch;
        } else if (require_labels) {
            return error.OutputSnapshotLabelMismatch;
        }
    }
}

/// Supported synchronous runtime surface for agent-vm execution.
pub const runtime = struct {
    /// Resource envelope for synchronous ArtifactV1 execution.
    pub const RunOptions = runtime_api.RunOptionsV1;

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
        return try runArtifactWithOptions(allocator, bytes, adapter, .{});
    }

    /// Execute artifact bytes through the supported runtime surface with explicit resource bounds.
    pub fn runArtifactWithOptions(
        allocator: std.mem.Allocator,
        bytes: []const u8,
        adapter: host.Adapter,
        options: RunOptions,
    ) anyerror!RunArtifactResult {
        var bridge_context: BridgeContext = .{
            .adapter = adapter,
            .data_value_bounds = options.data_value_bounds,
        };
        var internal_result = try runtime_api.runArtifactWithOptions(allocator, bytes, .{
            .ctx = &bridge_context,
            .dispatchFn = bridgeDispatch,
            .collectOutputsFn = bridgeCollectOutputs,
        }, options);
        defer internal_result.deinit(allocator);
        return try runArtifactResultFromInternal(allocator, internal_result, options.data_value_bounds);
    }
};

const BridgeContext = struct {
    adapter: host.Adapter,
    data_value_bounds: host_api.DataValueBoundsV1,
};

fn bridgeDispatch(
    ctx_ptr: ?*anyopaque,
    allocator: std.mem.Allocator,
    request: host_api.HostEffectRequestV1,
) anyerror!host_api.HostEffectResultV1 {
    const bridge_context: *BridgeContext = @ptrCast(@alignCast(ctx_ptr.?));
    var public_request = try requestFromInternal(allocator, request, bridge_context.data_value_bounds);
    defer public_request.deinit(allocator);

    var public_response = try bridge_context.adapter.dispatch(allocator, public_request);
    defer public_response.deinit(allocator);

    return try responseToInternal(allocator, request.request_id, public_response, bridge_context.data_value_bounds);
}

fn bridgeCollectOutputs(
    ctx_ptr: ?*anyopaque,
    allocator: std.mem.Allocator,
    declared_outputs: []const host_api.OutputDescriptorV1,
) anyerror![]host_api.DataValueV1 {
    const bridge_context: *BridgeContext = @ptrCast(@alignCast(ctx_ptr.?));
    const snapshots = try bridge_context.adapter.collectOutputSnapshots(allocator, declared_outputs);
    defer deinitOutputSnapshots(allocator, snapshots);

    try validateOutputSnapshotLabels(declared_outputs, snapshots, .allow_positional_single_output);
    const values = try allocator.alloc(host_api.DataValueV1, snapshots.len);
    var initialized: usize = 0;
    errdefer {
        for (values[0..initialized]) |*value| value.deinit(allocator);
        allocator.free(values);
    }
    for (snapshots, 0..) |snapshot, index| {
        values[index] = try snapshot.value.cloneBounded(allocator, bridge_context.data_value_bounds);
        initialized += 1;
    }
    return values;
}

fn runArtifactResultFromInternal(
    allocator: std.mem.Allocator,
    result: runtime_api.RunArtifactResultV1,
    bounds: host_api.DataValueBoundsV1,
) !runtime.RunArtifactResult {
    return switch (result) {
        .completed => |completed| .{ .completed = try executionResultFromInternal(allocator, completed, bounds) },
        .failed => |failure| .{ .failed = try hostFailureResultFromInternal(allocator, failure, bounds) },
        .rejected => |failure| .{ .rejected = try hostFailureResultFromInternal(allocator, failure, bounds) },
    };
}

fn executionResultFromInternal(
    allocator: std.mem.Allocator,
    result: runtime_api.ExecutionResultV1,
    bounds: host_api.DataValueBoundsV1,
) !runtime.ExecutionResult {
    var value = try dataValueFromProgramValueBounded(allocator, result.value, bounds);
    errdefer value.deinit(allocator);
    const outputs = try executionOutputsFromInternal(allocator, result.outputs, bounds);
    errdefer deinitExecutionOutputs(allocator, outputs);
    const logs = try hostLogsFromInternal(allocator, result.logs, bounds);
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
    bounds: host_api.DataValueBoundsV1,
) !runtime.HostFailureResult {
    var failure = try cloneFailureEnvelope(allocator, result.failure);
    errdefer failure.deinit(allocator);
    const logs = try hostLogsFromInternal(allocator, result.logs, bounds);
    errdefer deinitHostLogs(allocator, logs);
    return .{
        .failure = failure,
        .logs = logs,
    };
}

fn cloneFailureEnvelope(
    allocator: std.mem.Allocator,
    failure: host_api.FailureV1,
) !host.Failure {
    return try failure.cloneBounded(allocator, .{
        .max_depth = std.math.maxInt(usize),
        .max_nodes = std.math.maxInt(usize),
        .max_bytes = std.math.maxInt(usize),
    });
}

fn executionOutputsFromInternal(
    allocator: std.mem.Allocator,
    outputs: []const runtime_api.ExecutionOutputV1,
    bounds: host_api.DataValueBoundsV1,
) ![]runtime.ExecutionOutput {
    const owned_outputs = try allocator.alloc(runtime.ExecutionOutput, outputs.len);
    var initialized: usize = 0;
    errdefer deinitExecutionOutputsPrefix(allocator, owned_outputs, initialized);
    for (outputs, 0..) |output, index| {
        const label = try allocator.dupe(u8, output.label);
        errdefer allocator.free(label);
        const value = try output.value.cloneBounded(allocator, bounds);
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
    bounds: host_api.DataValueBoundsV1,
) ![]host.LogEntry {
    const owned_logs = try allocator.alloc(host.LogEntry, logs.len);
    var initialized: usize = 0;
    errdefer deinitHostLogsPrefix(allocator, owned_logs, initialized);
    for (logs, 0..) |entry, index| {
        owned_logs[index] = try hostLogFromInternal(allocator, entry, bounds);
        initialized += 1;
    }
    return owned_logs;
}

fn hostLogFromInternal(
    allocator: std.mem.Allocator,
    entry: host_api.HostLogEntryV1,
    bounds: host_api.DataValueBoundsV1,
) !host.LogEntry {
    var request = try requestFromInternal(allocator, entry.request, bounds);
    errdefer request.deinit(allocator);
    var response = try responseFromInternal(allocator, entry.result, bounds);
    errdefer response.deinit(allocator);
    return .{
        .request = request,
        .response = response,
    };
}

fn requestFromInternal(
    allocator: std.mem.Allocator,
    request: host_api.HostEffectRequestV1,
    bounds: host_api.DataValueBoundsV1,
) !host.Request {
    const tool_call = request.body.tool_call;
    const tool_id = try allocator.dupe(u8, tool_call.tool_id);
    errdefer allocator.free(tool_id);
    const op_name = try allocator.dupe(u8, tool_call.op_name);
    errdefer allocator.free(op_name);
    const payload = try tool_call.arguments.cloneBounded(allocator, bounds);
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
    bounds: host_api.DataValueBoundsV1,
) !host.Response {
    return switch (response.body) {
        .success => |value| switch (value.control) {
            .@"resume" => .{ .resumed = try cloneResumedResponse(allocator, response.request_id, value, bounds) },
            .return_now => .{ .return_now = try cloneTerminalResponse(allocator, response.request_id, value, bounds) },
            .abort => .{ .aborted = try cloneTerminalResponse(allocator, response.request_id, value, bounds) },
        },
        .rejected => |value| .{ .rejected = try value.cloneBounded(allocator, bounds) },
        .failed => |value| .{ .failed = try value.cloneBounded(allocator, bounds) },
    };
}

fn cloneResumedResponse(
    allocator: std.mem.Allocator,
    request_id: u64,
    value: host_api.ToolCallResultV1,
    bounds: host_api.DataValueBoundsV1,
) !host.Resumed {
    const cloned = try value.cloneBounded(allocator, bounds);
    errdefer {
        var owned = cloned;
        owned.deinit(allocator);
    }
    return .{
        .request_id = request_id,
        .tool_id = cloned.tool_id,
        .call_id = cloned.call_id,
        .value = cloned.value,
        .owns_tool_id = true,
        .value_ownership = .deep,
    };
}

fn cloneTerminalResponse(
    allocator: std.mem.Allocator,
    request_id: u64,
    value: host_api.ToolCallResultV1,
    bounds: host_api.DataValueBoundsV1,
) !host.Terminal {
    const cloned = try value.cloneBounded(allocator, bounds);
    errdefer {
        var owned = cloned;
        owned.deinit(allocator);
    }
    return .{
        .request_id = request_id,
        .tool_id = cloned.tool_id,
        .call_id = cloned.call_id,
        .value = cloned.value,
        .owns_tool_id = true,
        .value_ownership = .deep,
    };
}

fn responseToInternal(
    allocator: std.mem.Allocator,
    request_id: u64,
    response: host.Response,
    bounds: host_api.DataValueBoundsV1,
) !host_api.HostEffectResultV1 {
    return switch (response) {
        .resumed => |value| try cloneSuccessResult(allocator, request_id, .@"resume", value, bounds),
        .return_now => |value| try cloneSuccessResult(allocator, request_id, .return_now, value, bounds),
        .aborted => |value| try cloneSuccessResult(allocator, request_id, .abort, value, bounds),
        .rejected => |value| cloneFailureResponse(allocator, request_id, .rejected, value, bounds),
        .failed => |value| cloneFailureResponse(allocator, request_id, .failed, value, bounds),
    };
}

fn cloneSuccessResult(
    allocator: std.mem.Allocator,
    request_id: u64,
    control: host_api.ToolControlV1,
    value: anytype,
    bounds: host_api.DataValueBoundsV1,
) !host_api.HostEffectResultV1 {
    if (value.request_id != request_id) {
        return invalidHostReplyResult(allocator, request_id, "host reply request_id must echo the request");
    }
    const cloned = (host_api.ToolCallResultV1{
        .tool_id = value.tool_id,
        .call_id = value.call_id,
        .control = control,
        .value = value.value,
    }).cloneBounded(allocator, bounds) catch |err| switch (err) {
        error.DataValueTooDeep, error.DataValueTooManyNodes, error.DataValueTooManyBytes => {
            return resourceExhaustedResult(allocator, request_id, "artifact host payload budget exceeded");
        },
        else => return err,
    };
    errdefer {
        var owned = cloned;
        owned.deinit(allocator);
    }
    return .{
        .request_id = request_id,
        .body = .{ .success = .{
            .tool_id = cloned.tool_id,
            .call_id = cloned.call_id,
            .control = cloned.control,
            .value = cloned.value,
            .owns_tool_id = true,
            .value_ownership = .deep,
        } },
    };
}

fn cloneFailureResponse(
    allocator: std.mem.Allocator,
    request_id: u64,
    comptime status: host_api.HostEffectStatusV1,
    value: host.Failure,
    bounds: host_api.DataValueBoundsV1,
) !host_api.HostEffectResultV1 {
    const cloned_failure = value.cloneBounded(allocator, bounds) catch |err| switch (err) {
        error.DataValueTooDeep, error.DataValueTooManyNodes, error.DataValueTooManyBytes => {
            return resourceExhaustedResult(allocator, request_id, "artifact host payload budget exceeded");
        },
        else => return err,
    };
    return switch (status) {
        .rejected => .{
            .request_id = request_id,
            .body = .{ .rejected = cloned_failure },
        },
        .failed => .{
            .request_id = request_id,
            .body = .{ .failed = cloned_failure },
        },
        .success => unreachable,
    };
}

fn resourceExhaustedResult(
    allocator: std.mem.Allocator,
    request_id: u64,
    message: []const u8,
) !host_api.HostEffectResultV1 {
    const code = try allocator.dupe(u8, "resource_exhausted");
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

fn dataValueFromProgramValueBounded(
    allocator: std.mem.Allocator,
    value: anytype,
    bounds: host_api.DataValueBoundsV1,
) !host.DataValue {
    const public_value: host.DataValue = switch (value) {
        .none => .null,
        .bool => |typed| .{ .bool = typed },
        .i32 => |typed| .{ .i64 = typed },
        .usize => |typed| .{ .u64 = typed },
        .string => |typed| .{ .string = typed },
    };
    return try public_value.cloneBounded(allocator, bounds);
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

    var bridged = try requestFromInternal(std.testing.allocator, request, .{});
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

    var bridged = try responseToInternal(std.testing.allocator, 41, response, .{});
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

    var bridged = try responseToInternal(std.testing.allocator, request_id, response, .{});
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

    var bridged = try responseToInternal(std.testing.allocator, outer_request_id, response, .{});
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

    var bridged = try responseToInternal(allocator, 41, response, .{});
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

test "response bridge charges success tool ids against payload byte bounds" {
    var response: host.Response = .{ .resumed = .{
        .request_id = 41,
        .tool_id = "generated/tooling@v1",
        .call_id = 7,
        .value = .null,
    } };
    defer response.deinit(std.testing.allocator);

    var bridged = try responseToInternal(std.testing.allocator, 41, response, .{
        .max_bytes = 1,
    });
    defer bridged.deinit(std.testing.allocator);

    switch (bridged.body) {
        .failed => |failure| {
            try std.testing.expectEqualStrings("resource_exhausted", failure.code);
            try std.testing.expectEqualStrings("artifact host payload budget exceeded", failure.message);
        },
        else => return error.TestUnexpectedResponseKind,
    }
}

test "output bridge validates snapshot count before cloning payloads" {
    const allocator = std.testing.allocator;
    const descriptors = [_]host_api.OutputDescriptorV1{.{
        .label = "answer",
        .codec = .string,
    }};
    var bridge_context: BridgeContext = .{
        .adapter = .{
            .ctx = null,
            .dispatchFn = struct {
                fn dispatch(
                    _: ?*anyopaque,
                    _: std.mem.Allocator,
                    _: host.Request,
                ) anyerror!host.Response {
                    return error.TestUnexpectedDispatch;
                }
            }.dispatch,
            .collectOutputSnapshotsFn = struct {
                fn collect(
                    _: ?*anyopaque,
                    allocator_inner: std.mem.Allocator,
                    declared_outputs: []const host.OutputDescriptor,
                ) anyerror![]host.OutputSnapshot {
                    try std.testing.expectEqual(@as(usize, 1), declared_outputs.len);
                    const snapshots = try allocator_inner.alloc(host.OutputSnapshot, 2);
                    snapshots[0] = .{
                        .value = .{ .string = "this payload exceeds the configured clone byte limit" },
                        .value_ownership = .borrowed,
                    };
                    snapshots[1] = .{
                        .value = .null,
                        .value_ownership = .borrowed,
                    };
                    return snapshots;
                }
            }.collect,
        },
        .data_value_bounds = .{
            .max_depth = 4,
            .max_nodes = 8,
            .max_bytes = 1,
        },
    };

    try std.testing.expectError(
        error.OutputSnapshotCountMismatch,
        bridgeCollectOutputs(&bridge_context, allocator, &descriptors),
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

    const owned_outputs = try executionOutputsFromInternal(allocator, &outputs, .{});
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

    var bridged = try responseFromInternal(allocator, response, .{});
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
