const std = @import("std");

pub const ToolControlV1 = enum {
    @"resume",
    return_now,
    abort,
};

pub const DataValueV1 = union(enum) {
    null,
    bool: bool,
    i64: i64,
    string: []const u8,
    bytes: []u8,
    array: []DataValueV1,
    object: []ObjectFieldV1,

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !DataValueV1 {
        return switch (self) {
            .null => .null,
            .bool => |value| .{ .bool = value },
            .i64 => |value| .{ .i64 = value },
            .string => |value| .{ .string = try allocator.dupe(u8, value) },
            .bytes => |value| .{ .bytes = try allocator.dupe(u8, value) },
            .array => |items| blk: {
                const cloned = try allocator.alloc(DataValueV1, items.len);
                errdefer allocator.free(cloned);
                for (items, 0..) |item, index| cloned[index] = try item.clone(allocator);
                break :blk .{ .array = cloned };
            },
            .object => |fields| blk: {
                const cloned = try allocator.alloc(ObjectFieldV1, fields.len);
                errdefer allocator.free(cloned);
                for (fields, 0..) |field, index| {
                    cloned[index] = .{
                        .key = try allocator.dupe(u8, field.key),
                        .value = try field.value.clone(allocator),
                    };
                }
                break :blk .{ .object = cloned };
            },
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .null, .bool, .i64 => {},
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

pub const ObjectFieldV1 = struct {
    key: []const u8,
    value: DataValueV1,
};

pub const ToolCallRequestV1 = struct {
    tool_id: []const u8,
    call_id: u64,
    op_name: []const u8,
    arguments: DataValueV1,

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
        return .{
            .tool_id = try allocator.dupe(u8, self.tool_id),
            .call_id = self.call_id,
            .op_name = try allocator.dupe(u8, self.op_name),
            .arguments = try self.arguments.clone(allocator),
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.tool_id);
        allocator.free(self.op_name);
        self.arguments.deinit(allocator);
        self.* = undefined;
    }
};

pub const ToolCallResultV1 = struct {
    tool_id: []const u8,
    call_id: u64,
    control: ToolControlV1 = .@"resume",
    value: DataValueV1,

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
        return .{
            .tool_id = try allocator.dupe(u8, self.tool_id),
            .call_id = self.call_id,
            .control = self.control,
            .value = try self.value.clone(allocator),
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.tool_id);
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

pub const FailureV1 = struct {
    code: []const u8,
    message: []const u8,

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
        return .{
            .code = try allocator.dupe(u8, self.code),
            .message = try allocator.dupe(u8, self.message),
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.message);
        self.* = undefined;
    }
};

pub const HostEffectKindV1 = enum {
    model_turn,
    tool_call,
    durable_load,
    durable_store,
};

pub const HostEffectRequestBodyV1 = union(HostEffectKindV1) {
    model_turn: void,
    tool_call: ToolCallRequestV1,
    durable_load: void,
    durable_store: void,

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
        return switch (self) {
            .model_turn => .{ .model_turn = {} },
            .tool_call => |value| .{ .tool_call = try value.clone(allocator) },
            .durable_load => .{ .durable_load = {} },
            .durable_store => .{ .durable_store = {} },
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .tool_call => |*value| value.deinit(allocator),
            else => {},
        }
        self.* = undefined;
    }
};

pub const HostEffectRequestV1 = struct {
    schema_version: u16 = 1,
    request_id: u64,
    capability_id: u16,
    op_id: u16,
    body: HostEffectRequestBodyV1,

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
        return .{
            .schema_version = self.schema_version,
            .request_id = self.request_id,
            .capability_id = self.capability_id,
            .op_id = self.op_id,
            .body = try self.body.clone(allocator),
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.body.deinit(allocator);
        self.* = undefined;
    }
};

pub const HostEffectStatusV1 = enum {
    ok,
    rejected,
    failed,
};

pub const HostEffectResultBodyV1 = union(HostEffectStatusV1) {
    ok: ToolCallResultV1,
    rejected: FailureV1,
    failed: FailureV1,

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
        return switch (self) {
            .ok => |value| .{ .ok = try value.clone(allocator) },
            .rejected => |value| .{ .rejected = try value.clone(allocator) },
            .failed => |value| .{ .failed = try value.clone(allocator) },
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => |*value| value.deinit(allocator),
            .rejected => |*value| value.deinit(allocator),
            .failed => |*value| value.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const HostEffectResultV1 = struct {
    schema_version: u16 = 1,
    request_id: u64,
    body: HostEffectResultBodyV1,

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
        return .{
            .schema_version = self.schema_version,
            .request_id = self.request_id,
            .body = try self.body.clone(allocator),
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.body.deinit(allocator);
        self.* = undefined;
    }
};

pub const HostLogEntryV1 = struct {
    request: HostEffectRequestV1,
    result: HostEffectResultV1,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.request.deinit(allocator);
        self.result.deinit(allocator);
        self.* = undefined;
    }
};

pub const HostAdapterV1 = struct {
    ctx: *anyopaque,
    dispatchFn: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, request: HostEffectRequestV1) anyerror!HostEffectResultV1,

    pub fn dispatch(self: @This(), allocator: std.mem.Allocator, request: HostEffectRequestV1) anyerror!HostEffectResultV1 {
        return self.dispatchFn(self.ctx, allocator, request);
    }
};
