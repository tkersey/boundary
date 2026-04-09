const std = @import("std");

/// Control outcome returned by one synchronous host tool call.
pub const ToolControlV1 = enum {
    @"resume",
    abort,
    return_now,
};

/// Typed recursive value tree used by HostAdapterV1 request and result payloads.
pub const DataValueV1 = union(enum) {
    array: []DataValueV1,
    bool: bool,
    bytes: []u8,
    i64: i64,
    null,
    object: []ObjectFieldV1,
    string: []const u8,
    u64: u64,

    /// Clone one typed payload tree into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!DataValueV1 {
        return switch (self) {
            .null => .null,
            .bool => |value| .{ .bool = value },
            .i64 => |value| .{ .i64 = value },
            .u64 => |value| .{ .u64 = value },
            .string => |value| .{ .string = try allocator.dupe(u8, value) },
            .bytes => |value| .{ .bytes = try allocator.dupe(u8, value) },
            .array => |items| blk: {
                const cloned = try allocator.alloc(DataValueV1, items.len);
                errdefer allocator.free(cloned);
                var cloned_len: usize = 0;
                errdefer for (cloned[0..cloned_len]) |*item| item.deinit(allocator);
                for (items, 0..) |item, index| {
                    cloned[index] = try item.clone(allocator);
                    cloned_len += 1;
                }
                break :blk .{ .array = cloned };
            },
            .object => |fields| blk: {
                const cloned = try allocator.alloc(ObjectFieldV1, fields.len);
                errdefer allocator.free(cloned);
                var cloned_len: usize = 0;
                errdefer {
                    for (cloned[0..cloned_len]) |*field| {
                        allocator.free(field.key);
                        field.value.deinit(allocator);
                    }
                }
                for (fields, 0..) |field, index| {
                    cloned[index] = try cloneObjectField(field, allocator);
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
                for (items) |*item| item.deinit(allocator);
                allocator.free(items);
            },
            .object => |fields| {
                for (fields) |*field| {
                    allocator.free(field.key);
                    field.value.deinit(allocator);
                }
                allocator.free(fields);
            },
        }
        self.* = undefined;
    }
};

/// One object field carried inside `DataValueV1.object`.
pub const ObjectFieldV1 = struct {
    key: []const u8,
    value: DataValueV1,
};

fn cloneObjectField(field: ObjectFieldV1, allocator: std.mem.Allocator) !ObjectFieldV1 {
    const key = try allocator.dupe(u8, field.key);
    errdefer allocator.free(key);
    const value = try field.value.clone(allocator);
    errdefer {
        var owned_value = value;
        owned_value.deinit(allocator);
    }
    return .{
        .key = key,
        .value = value,
    };
}

/// Typed tool-call request body used by HostAdapterV1.
pub const ToolCallRequestV1 = struct {
    tool_id: []const u8,
    call_id: u64,
    op_name: []const u8,
    arguments: DataValueV1,

    /// Clone one tool-call request into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {
        const tool_id = try allocator.dupe(u8, self.tool_id);
        errdefer allocator.free(tool_id);
        const op_name = try allocator.dupe(u8, self.op_name);
        errdefer allocator.free(op_name);
        const arguments = try self.arguments.clone(allocator);
        errdefer {
            var owned_arguments = arguments;
            owned_arguments.deinit(allocator);
        }
        return .{
            .tool_id = tool_id,
            .call_id = self.call_id,
            .op_name = op_name,
            .arguments = arguments,
        };
    }

    /// Release any allocator-owned memory held by this tool-call request.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.tool_id);
        allocator.free(self.op_name);
        self.arguments.deinit(allocator);
        self.* = undefined;
    }
};

/// Typed tool-call result body used by HostAdapterV1.
pub const ToolCallResultV1 = struct {
    tool_id: []const u8,
    call_id: u64,
    control: ToolControlV1 = .@"resume",
    value: DataValueV1,

    /// Clone one tool-call result into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {
        const tool_id = try allocator.dupe(u8, self.tool_id);
        errdefer allocator.free(tool_id);
        const value = try self.value.clone(allocator);
        errdefer {
            var owned_value = value;
            owned_value.deinit(allocator);
        }
        return .{
            .tool_id = tool_id,
            .call_id = self.call_id,
            .control = self.control,
            .value = value,
        };
    }

    /// Release any allocator-owned memory held by this tool-call result.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.tool_id);
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

/// Typed failure payload returned across HostAdapterV1.
pub const FailureV1 = struct {
    code: []const u8,
    message: []const u8,

    /// Clone one failure payload into allocator-owned memory.
    pub fn clone(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {
        const code = try allocator.dupe(u8, self.code);
        errdefer allocator.free(code);
        return .{
            .code = code,
            .message = try allocator.dupe(u8, self.message),
        };
    }

    /// Release any allocator-owned memory held by this failure payload.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.message);
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
        return switch (self) {
            .tool_call => |value| .{ .tool_call = try value.clone(allocator) },
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
        return .{
            .schema_version = self.schema_version,
            .request_id = self.request_id,
            .capability_id = self.capability_id,
            .op_id = self.op_id,
            .body = try self.body.clone(allocator),
        };
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
        return switch (self) {
            .success => |value| .{ .success = try value.clone(allocator) },
            .rejected => |value| .{ .rejected = try value.clone(allocator) },
            .failed => |value| .{ .failed = try value.clone(allocator) },
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
        return .{
            .schema_version = self.schema_version,
            .request_id = self.request_id,
            .body = try self.body.clone(allocator),
        };
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
};

/// Synchronous host dispatch interface used by the ArtifactV1 VM runtime.
pub const HostAdapterV1 = struct {
    ctx: *anyopaque,
    dispatchFn: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, request: HostEffectRequestV1) anyerror!HostEffectResultV1,

    /// Dispatch one synchronous host-effect request.
    pub fn dispatch(self: @This(), allocator: std.mem.Allocator, request: HostEffectRequestV1) anyerror!HostEffectResultV1 {
        return self.dispatchFn(self.ctx, allocator, request);
    }
};
