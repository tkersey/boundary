const std = @import("std");

/// Control outcome returned by one synchronous host tool call.
pub const ToolControlV1 = enum {
    @"resume",
    abort,
    return_now,
};

/// Ownership mode for request/result payload trees.
pub const DataValueOwnershipV1 = enum {
    borrowed,
    container,
    deep,
};

/// Defensive bounds for cloning recursive host payload trees.
pub const DataValueBoundsV1 = struct {
    max_depth: usize = 64,
    max_nodes: usize = 4096,
    max_bytes: usize = 1 << 20,
};

const DataValueCloneState = struct {
    nodes: usize = 0,
    bytes: usize = 0,

    fn chargeNode(self: *@This(), bounds: DataValueBoundsV1) !void {
        self.nodes = std.math.add(usize, self.nodes, 1) catch return error.DataValueTooManyNodes;
        if (self.nodes > bounds.max_nodes) return error.DataValueTooManyNodes;
    }

    fn chargeBytes(self: *@This(), bounds: DataValueBoundsV1, count: usize) !void {
        self.bytes = std.math.add(usize, self.bytes, count) catch return error.DataValueTooManyBytes;
        if (self.bytes > bounds.max_bytes) return error.DataValueTooManyBytes;
    }

    fn canFitNodes(self: @This(), bounds: DataValueBoundsV1, count: usize) bool {
        if (self.nodes > bounds.max_nodes) return false;
        return count <= bounds.max_nodes - self.nodes;
    }
};

/// Declared output codecs surfaced by the ArtifactV1 runtime completion hook.
pub const OutputCodecV1 = enum {
    bool,
    i32,
    string,
    string_list,
    unit,
    usize,
};

/// One declared ArtifactV1 entry output surfaced to the host completion hook.
pub const OutputDescriptorV1 = struct {
    label: []const u8,
    codec: OutputCodecV1,
};

/// Typed recursive value tree used by HostAdapterV1 request and result payloads.
pub const DataValueV1 = union(enum) {
    array: []const DataValueV1,
    bool: bool,
    bytes: []const u8,
    i64: i64,
    null,
    object: []const ObjectFieldV1,
    string: []const u8,
    u64: u64,

    /// Clone one typed payload tree into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!DataValueV1 {
        return try self.cloneBounded(allocator, .{});
    }

    /// Clone one typed payload tree with explicit recursion and size limits.
    pub fn cloneBounded(self: @This(), allocator: std.mem.Allocator, bounds: DataValueBoundsV1) anyerror!DataValueV1 {
        var state = DataValueCloneState{};
        return try self.cloneBoundedInner(allocator, bounds, &state, 0);
    }

    /// Count the string/byte payload footprint under the same tree bounds used for cloning.
    pub fn boundedByteSize(self: @This(), bounds: DataValueBoundsV1) anyerror!usize {
        var state = DataValueCloneState{};
        try self.chargeBoundedInner(bounds, &state, 0);
        return state.bytes;
    }

    fn chargeBoundedInner(
        self: @This(),
        bounds: DataValueBoundsV1,
        state: *DataValueCloneState,
        depth: usize,
    ) anyerror!void {
        if (depth > bounds.max_depth) return error.DataValueTooDeep;
        try state.chargeNode(bounds);
        switch (self) {
            .null, .bool, .i64, .u64 => {},
            .string, .bytes => |value| try state.chargeBytes(bounds, value.len),
            .array => |items| {
                if (!state.canFitNodes(bounds, items.len)) return error.DataValueTooManyNodes;
                for (items) |item| try item.chargeBoundedInner(bounds, state, depth + 1);
            },
            .object => |fields| {
                if (!state.canFitNodes(bounds, fields.len)) return error.DataValueTooManyNodes;
                for (fields) |field| {
                    try state.chargeBytes(bounds, field.key.len);
                    try field.value.chargeBoundedInner(bounds, state, depth + 1);
                }
            },
        }
    }

    fn cloneBoundedInner(
        self: @This(),
        allocator: std.mem.Allocator,
        bounds: DataValueBoundsV1,
        state: *DataValueCloneState,
        depth: usize,
    ) anyerror!DataValueV1 {
        if (depth > bounds.max_depth) return error.DataValueTooDeep;
        try state.chargeNode(bounds);
        return switch (self) {
            .null => .null,
            .bool => |value| .{ .bool = value },
            .i64 => |value| .{ .i64 = value },
            .u64 => |value| .{ .u64 = value },
            .string => |value| blk: {
                try state.chargeBytes(bounds, value.len);
                break :blk .{ .string = try allocator.dupe(u8, value) };
            },
            .bytes => |value| blk: {
                try state.chargeBytes(bounds, value.len);
                break :blk .{ .bytes = try allocator.dupe(u8, value) };
            },
            .array => |items| blk: {
                if (!state.canFitNodes(bounds, items.len)) return error.DataValueTooManyNodes;
                const cloned = try allocator.alloc(DataValueV1, items.len);
                errdefer allocator.free(cloned);
                var cloned_len: usize = 0;
                errdefer for (cloned[0..cloned_len]) |*item| item.deinit(allocator);
                for (items, 0..) |item, index| {
                    cloned[index] = try item.cloneBoundedInner(allocator, bounds, state, depth + 1);
                    cloned_len += 1;
                }
                break :blk .{ .array = cloned };
            },
            .object => |fields| blk: {
                if (!state.canFitNodes(bounds, fields.len)) return error.DataValueTooManyNodes;
                const cloned = try allocator.alloc(ObjectFieldV1, fields.len);
                errdefer allocator.free(cloned);
                var cloned_len: usize = 0;
                errdefer {
                    for (cloned[0..cloned_len]) |*field| {
                        if (field.owns_key) allocator.free(field.key);
                        field.value.deinit(allocator);
                    }
                }
                for (fields, 0..) |field, index| {
                    cloned[index] = try cloneObjectFieldBounded(field, allocator, bounds, state, depth + 1);
                    cloned_len += 1;
                }
                break :blk .{ .object = cloned };
            },
        };
    }

    /// Release any allocator-owned memory held by this typed payload tree.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .null, .bool, .i64, .u64 => {},
            .string => |value| allocator.free(value),
            .bytes => |value| allocator.free(value),
            .array => |items| {
                const mutable_items = @constCast(items);
                for (mutable_items) |*item| item.deinit(allocator);
                allocator.free(mutable_items);
            },
            .object => |fields| {
                const mutable_fields = @constCast(fields);
                for (mutable_fields) |*field| {
                    if (field.owns_key) allocator.free(field.key);
                    field.value.deinit(allocator);
                }
                allocator.free(mutable_fields);
            },
        }
        self.* = undefined;
    }

    /// Release only allocator-owned array/object storage while treating leaves as borrowed.
    pub fn deinitContainers(self: *@This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .null, .bool, .bytes, .i64, .string, .u64 => {},
            .array => |items| {
                const mutable_items = @constCast(items);
                for (mutable_items) |*item| item.deinitContainers(allocator);
                allocator.free(mutable_items);
            },
            .object => |fields| {
                const mutable_fields = @constCast(fields);
                for (mutable_fields) |*field| {
                    if (field.owns_key) allocator.free(field.key);
                    field.value.deinitContainers(allocator);
                }
                allocator.free(mutable_fields);
            },
        }
        self.* = .null;
    }

    /// Release this payload according to the wrapper's declared ownership mode.
    pub fn deinitWithOwnership(
        self: *@This(),
        allocator: std.mem.Allocator,
        ownership: DataValueOwnershipV1,
    ) void {
        switch (ownership) {
            .borrowed => self.* = .null,
            .container => self.deinitContainers(allocator),
            .deep => self.deinit(allocator),
        }
    }
};

/// One object field carried inside `DataValueV1.object`.
pub const ObjectFieldV1 = struct {
    key: []const u8,
    owns_key: bool = false,
    value: DataValueV1,
};

fn cloneObjectFieldBounded(
    field: ObjectFieldV1,
    allocator: std.mem.Allocator,
    bounds: DataValueBoundsV1,
    state: *DataValueCloneState,
    depth: usize,
) !ObjectFieldV1 {
    try state.chargeBytes(bounds, field.key.len);
    const key = try allocator.dupe(u8, field.key);
    errdefer allocator.free(key);
    const value = try field.value.cloneBoundedInner(allocator, bounds, state, depth);
    errdefer {
        var owned_value = value;
        owned_value.deinit(allocator);
    }
    return .{
        .key = key,
        .owns_key = true,
        .value = value,
    };
}

/// Typed tool-call request body used by HostAdapterV1.
pub const ToolCallRequestV1 = struct {
    tool_id: []const u8,
    call_id: u64,
    op_name: []const u8,
    arguments: DataValueV1,
    owns_tool_id: bool = false,
    owns_op_name: bool = false,
    arguments_ownership: DataValueOwnershipV1 = .borrowed,

    /// Clone one tool-call request into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {
        return try self.cloneBounded(allocator, .{});
    }

    /// Clone one tool-call request into allocator-owned memory with bounded payload cloning.
    pub fn cloneBounded(self: @This(), allocator: std.mem.Allocator, bounds: DataValueBoundsV1) anyerror!@This() {
        var state = DataValueCloneState{};
        try state.chargeBytes(bounds, self.tool_id.len);
        try state.chargeBytes(bounds, self.op_name.len);
        const tool_id = try allocator.dupe(u8, self.tool_id);
        errdefer allocator.free(tool_id);
        const op_name = try allocator.dupe(u8, self.op_name);
        errdefer allocator.free(op_name);
        const arguments = try self.arguments.cloneBoundedInner(allocator, bounds, &state, 0);
        errdefer {
            var owned_arguments = arguments;
            owned_arguments.deinit(allocator);
        }
        return .{
            .tool_id = tool_id,
            .call_id = self.call_id,
            .op_name = op_name,
            .arguments = arguments,
            .owns_tool_id = true,
            .owns_op_name = true,
            .arguments_ownership = .deep,
        };
    }

    /// Count request metadata and payload bytes under the same bounds used for cloning.
    pub fn boundedByteSize(self: @This(), bounds: DataValueBoundsV1) anyerror!usize {
        var state = DataValueCloneState{};
        try state.chargeBytes(bounds, self.tool_id.len);
        try state.chargeBytes(bounds, self.op_name.len);
        try self.arguments.chargeBoundedInner(bounds, &state, 0);
        return state.bytes;
    }

    /// Release any allocator-owned memory held by this tool-call request.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.owns_tool_id) allocator.free(self.tool_id);
        if (self.owns_op_name) allocator.free(self.op_name);
        self.arguments.deinitWithOwnership(allocator, self.arguments_ownership);
        self.* = undefined;
    }
};

/// Typed tool-call result body used by HostAdapterV1.
pub const ToolCallResultV1 = struct {
    tool_id: []const u8,
    call_id: u64,
    control: ToolControlV1 = .@"resume",
    value: DataValueV1,
    owns_tool_id: bool = false,
    value_ownership: DataValueOwnershipV1 = .borrowed,

    /// Clone one tool-call result into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {
        return try self.cloneBounded(allocator, .{});
    }

    /// Clone one tool-call result into allocator-owned memory with bounded payload cloning.
    pub fn cloneBounded(self: @This(), allocator: std.mem.Allocator, bounds: DataValueBoundsV1) anyerror!@This() {
        var state = DataValueCloneState{};
        try state.chargeBytes(bounds, self.tool_id.len);
        const tool_id = try allocator.dupe(u8, self.tool_id);
        errdefer allocator.free(tool_id);
        const value = try self.value.cloneBoundedInner(allocator, bounds, &state, 0);
        errdefer {
            var owned_value = value;
            owned_value.deinit(allocator);
        }
        return .{
            .tool_id = tool_id,
            .call_id = self.call_id,
            .control = self.control,
            .value = value,
            .owns_tool_id = true,
            .value_ownership = .deep,
        };
    }

    /// Count result metadata and payload bytes under the same bounds used for cloning.
    pub fn boundedByteSize(self: @This(), bounds: DataValueBoundsV1) anyerror!usize {
        var state = DataValueCloneState{};
        try state.chargeBytes(bounds, self.tool_id.len);
        try self.value.chargeBoundedInner(bounds, &state, 0);
        return state.bytes;
    }

    /// Release any allocator-owned memory held by this tool-call result.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.owns_tool_id) allocator.free(self.tool_id);
        self.value.deinitWithOwnership(allocator, self.value_ownership);
        self.* = undefined;
    }
};

/// Typed failure payload returned across HostAdapterV1.
pub const FailureV1 = struct {
    code: []const u8,
    message: []const u8,
    owns_code: bool = false,
    owns_message: bool = false,

    /// Clone one failure payload into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {
        return try self.cloneBounded(allocator, .{});
    }

    /// Clone one failure payload into allocator-owned memory with bounded text size.
    pub fn cloneBounded(self: @This(), allocator: std.mem.Allocator, bounds: DataValueBoundsV1) anyerror!@This() {
        var state = DataValueCloneState{};
        try state.chargeBytes(bounds, self.code.len);
        try state.chargeBytes(bounds, self.message.len);
        const code = try allocator.dupe(u8, self.code);
        errdefer allocator.free(code);
        return .{
            .code = code,
            .message = try allocator.dupe(u8, self.message),
            .owns_code = true,
            .owns_message = true,
        };
    }

    /// Count failure payload bytes under the same bounds used for cloning.
    pub fn boundedByteSize(self: @This(), bounds: DataValueBoundsV1) anyerror!usize {
        var state = DataValueCloneState{};
        try state.chargeBytes(bounds, self.code.len);
        try state.chargeBytes(bounds, self.message.len);
        return state.bytes;
    }

    /// Release any allocator-owned memory held by this failure payload.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.owns_code) allocator.free(self.code);
        if (self.owns_message) allocator.free(self.message);
        self.* = undefined;
    }
};

/// Host effect kinds supported by HostAdapterV1.
pub const HostEffectKindV1 = enum {
    tool_call,
};

/// Request-body variants supported by HostAdapterV1.
pub const HostEffectRequestBodyV1 = union(HostEffectKindV1) {
    tool_call: ToolCallRequestV1,

    /// Clone one request-body variant into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {
        return try self.cloneBounded(allocator, .{});
    }

    /// Clone one request-body variant into allocator-owned memory with bounded payload cloning.
    pub fn cloneBounded(self: @This(), allocator: std.mem.Allocator, bounds: DataValueBoundsV1) anyerror!@This() {
        return switch (self) {
            .tool_call => |value| .{ .tool_call = try value.cloneBounded(allocator, bounds) },
        };
    }

    /// Count request-body bytes under the same bounds used for cloning.
    pub fn boundedByteSize(self: @This(), bounds: DataValueBoundsV1) anyerror!usize {
        return switch (self) {
            .tool_call => |value| try value.boundedByteSize(bounds),
        };
    }

    /// Release any allocator-owned memory held by this request-body variant.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .tool_call => |*value| value.deinit(allocator),
        }
        self.* = undefined;
    }
};

/// One synchronous host-effect request.
pub const HostEffectRequestV1 = struct {
    schema_version: u16 = 1,
    request_id: u64,
    capability_id: u16,
    op_id: u16,
    body: HostEffectRequestBodyV1,

    /// Clone one host-effect request into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {
        return try self.cloneBounded(allocator, .{});
    }

    /// Clone one host-effect request into allocator-owned memory with bounded payload cloning.
    pub fn cloneBounded(self: @This(), allocator: std.mem.Allocator, bounds: DataValueBoundsV1) anyerror!@This() {
        return .{
            .schema_version = self.schema_version,
            .request_id = self.request_id,
            .capability_id = self.capability_id,
            .op_id = self.op_id,
            .body = try self.body.cloneBounded(allocator, bounds),
        };
    }

    /// Count host-effect request bytes under the same bounds used for cloning.
    pub fn boundedByteSize(self: @This(), bounds: DataValueBoundsV1) anyerror!usize {
        return try self.body.boundedByteSize(bounds);
    }

    /// Release any allocator-owned memory held by this host-effect request.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.body.deinit(allocator);
        self.* = undefined;
    }
};

/// Result status returned by one synchronous host-effect request.
pub const HostEffectStatusV1 = enum {
    failed,
    rejected,
    success,
};

/// Result-body variants returned by HostAdapterV1.
pub const HostEffectResultBodyV1 = union(HostEffectStatusV1) {
    failed: FailureV1,
    rejected: FailureV1,
    success: ToolCallResultV1,

    /// Clone one result-body variant into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {
        return try self.cloneBounded(allocator, .{});
    }

    /// Clone one result-body variant into allocator-owned memory with bounded payload cloning.
    pub fn cloneBounded(self: @This(), allocator: std.mem.Allocator, bounds: DataValueBoundsV1) anyerror!@This() {
        return switch (self) {
            .success => |value| .{ .success = try value.cloneBounded(allocator, bounds) },
            .rejected => |value| .{ .rejected = try value.cloneBounded(allocator, bounds) },
            .failed => |value| .{ .failed = try value.cloneBounded(allocator, bounds) },
        };
    }

    /// Count result-body bytes under the same bounds used for cloning.
    pub fn boundedByteSize(self: @This(), bounds: DataValueBoundsV1) anyerror!usize {
        return switch (self) {
            .success => |value| try value.boundedByteSize(bounds),
            .rejected => |value| try value.boundedByteSize(bounds),
            .failed => |value| try value.boundedByteSize(bounds),
        };
    }

    /// Release any allocator-owned memory held by this result-body variant.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .success => |*value| value.deinit(allocator),
            .rejected => |*value| value.deinit(allocator),
            .failed => |*value| value.deinit(allocator),
        }
        self.* = undefined;
    }
};

/// One synchronous host-effect result.
pub const HostEffectResultV1 = struct {
    schema_version: u16 = 1,
    request_id: u64,
    body: HostEffectResultBodyV1,

    /// Clone one host-effect result into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {
        return try self.cloneBounded(allocator, .{});
    }

    /// Clone one host-effect result into allocator-owned memory with bounded payload cloning.
    pub fn cloneBounded(self: @This(), allocator: std.mem.Allocator, bounds: DataValueBoundsV1) anyerror!@This() {
        return .{
            .schema_version = self.schema_version,
            .request_id = self.request_id,
            .body = try self.body.cloneBounded(allocator, bounds),
        };
    }

    /// Count host-effect result bytes under the same bounds used for cloning.
    pub fn boundedByteSize(self: @This(), bounds: DataValueBoundsV1) anyerror!usize {
        return try self.body.boundedByteSize(bounds);
    }

    /// Release any allocator-owned memory held by this host-effect result.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.body.deinit(allocator);
        self.* = undefined;
    }
};

/// One logged HostAdapterV1 request/result pair.
pub const HostLogEntryV1 = struct {
    request: HostEffectRequestV1,
    result: HostEffectResultV1,

    /// Release any allocator-owned memory held by this logged request/result pair.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.request.deinit(allocator);
        self.result.deinit(allocator);
        self.* = undefined;
    }

    /// Count logged request/result bytes under the same bounds used for cloning.
    pub fn boundedByteSize(self: @This(), bounds: DataValueBoundsV1) anyerror!usize {
        const request_bytes = try self.request.boundedByteSize(bounds);
        const result_bytes = try self.result.boundedByteSize(bounds);
        return std.math.add(usize, request_bytes, result_bytes) catch error.DataValueTooManyBytes;
    }
};

/// Synchronous host dispatch interface used by the ArtifactV1 VM runtime.
pub const HostAdapterV1 = struct {
    ctx: ?*anyopaque,
    dispatchFn: *const fn (ctx: ?*anyopaque, allocator: std.mem.Allocator, request: HostEffectRequestV1) anyerror!HostEffectResultV1,
    /// Optional completion hook for declared ArtifactV1 entry outputs.
    /// Returned values must be allocator-owned and match the declared outputs exactly.
    collectOutputsFn: ?*const fn (ctx: ?*anyopaque, allocator: std.mem.Allocator, declared_outputs: []const OutputDescriptorV1) anyerror![]DataValueV1 = null,

    /// Dispatch one synchronous host-effect request.
    pub fn dispatch(self: @This(), allocator: std.mem.Allocator, request: HostEffectRequestV1) anyerror!HostEffectResultV1 {
        return self.dispatchFn(self.ctx, allocator, request);
    }

    /// Collect one declared entry-output bundle after the ArtifactV1 root completes.
    pub fn collectOutputs(
        self: @This(),
        allocator: std.mem.Allocator,
        declared_outputs: []const OutputDescriptorV1,
    ) anyerror![]DataValueV1 {
        if (declared_outputs.len == 0) return allocator.alloc(DataValueV1, 0);
        const collect = self.collectOutputsFn orelse return error.MissingOutputSnapshot;
        return collect(self.ctx, allocator, declared_outputs);
    }
};

test "DataValueV1 bounded clone rejects excessive recursion depth" {
    const allocator = std.testing.allocator;
    const leaf = [_]DataValueV1{.null};
    const root: DataValueV1 = .{ .array = &leaf };

    try std.testing.expectError(error.DataValueTooDeep, root.cloneBounded(allocator, .{
        .max_depth = 0,
        .max_nodes = 8,
        .max_bytes = 1024,
    }));
}

test "DataValueV1 bounded clone rejects excessive node count" {
    const CountingAllocator = struct {
        child: std.mem.Allocator,
        alloc_calls: usize = 0,

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
            self.child.rawFree(memory, alignment, ret_addr);
        }
    };

    var counting: CountingAllocator = .{ .child = std.testing.allocator };
    const allocator = counting.allocator();
    const values = [_]DataValueV1{ .null, .null };
    const root: DataValueV1 = .{ .array = &values };

    try std.testing.expectError(error.DataValueTooManyNodes, root.cloneBounded(allocator, .{
        .max_depth = 4,
        .max_nodes = 2,
        .max_bytes = 1024,
    }));
    try std.testing.expectEqual(@as(usize, 0), counting.alloc_calls);
}

test "DataValueV1 bounded clone rejects excessive byte count" {
    const allocator = std.testing.allocator;
    const root: DataValueV1 = .{ .string = "oversized" };

    try std.testing.expectError(error.DataValueTooManyBytes, root.cloneBounded(allocator, .{
        .max_depth = 4,
        .max_nodes = 8,
        .max_bytes = 4,
    }));
}

test "FailureV1 bounded clone rejects excessive byte count" {
    const allocator = std.testing.allocator;
    const failure: FailureV1 = .{
        .code = "provider_failure",
        .message = "oversized failure message",
    };

    try std.testing.expectError(error.DataValueTooManyBytes, failure.cloneBounded(allocator, .{
        .max_depth = 4,
        .max_nodes = 8,
        .max_bytes = 8,
    }));
}

test "ToolCallRequestV1 bounded clone charges metadata bytes" {
    const allocator = std.testing.allocator;
    const request: ToolCallRequestV1 = .{
        .tool_id = "tooling",
        .call_id = 1,
        .op_name = "dispatch",
        .arguments = .null,
    };

    try std.testing.expectError(error.DataValueTooManyBytes, request.cloneBounded(allocator, .{
        .max_depth = 4,
        .max_nodes = 8,
        .max_bytes = 4,
    }));
}

test "ToolCallResultV1 bounded clone charges metadata bytes" {
    const allocator = std.testing.allocator;
    const result: ToolCallResultV1 = .{
        .tool_id = "oversized-tool-id",
        .call_id = 1,
        .value = .null,
    };

    try std.testing.expectError(error.DataValueTooManyBytes, result.cloneBounded(allocator, .{
        .max_depth = 4,
        .max_nodes = 8,
        .max_bytes = 4,
    }));
}
