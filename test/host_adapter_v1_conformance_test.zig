const conformance = @import("host_adapter_v1_conformance");
const host = @import("shift_vm").host_adapter;
const std = @import("std");

test "host adapter conformance helper enforces sequential ids and tool echo" {
    var entries = [_]host.HostLogEntryV1{
        .{
            .request = .{
                .request_id = 1,
                .capability_id = 0,
                .op_id = 0,
                .body = .{ .tool_call = .{
                    .tool_id = try std.testing.allocator.dupe(u8, "generated/tooling@v1"),
                    .call_id = 1,
                    .op_name = try std.testing.allocator.dupe(u8, "tell"),
                    .arguments = .{ .string = try std.testing.allocator.dupe(u8, "queued") },
                    .owns_tool_id = true,
                    .owns_op_name = true,
                    .arguments_ownership = .deep,
                } },
            },
            .result = .{
                .request_id = 1,
                .body = .{ .success = .{
                    .tool_id = try std.testing.allocator.dupe(u8, "generated/tooling@v1"),
                    .call_id = 1,
                    .control = .@"resume",
                    .value = .null,
                    .owns_tool_id = true,
                } },
            },
        },
    };
    defer for (&entries) |*entry| entry.deinit(std.testing.allocator);

    try conformance.assertSequentialRequestIds(&entries);
    try conformance.assertToolCallShape(entries[0], "generated/tooling@v1", "tell");
}

fn cloneArrayPayload(allocator: std.mem.Allocator) !void {
    var items = [_]host.DataValueV1{
        .{ .string = "first" },
        .{ .string = "second" },
    };
    const value: host.DataValueV1 = .{ .array = items[0..] };
    var cloned = try value.clone(allocator);
    defer cloned.deinit(allocator);
}

fn cloneObjectPayload(allocator: std.mem.Allocator) !void {
    var fields = [_]host.ObjectFieldV1{
        .{ .key = "alpha", .value = .{ .string = "first" } },
        .{ .key = "beta", .value = .{ .string = "second" } },
    };
    const value: host.DataValueV1 = .{ .object = fields[0..] };
    var cloned = try value.clone(allocator);
    defer cloned.deinit(allocator);
}

fn cloneToolCallRequest(allocator: std.mem.Allocator) !void {
    var fields = [_]host.ObjectFieldV1{
        .{ .key = "alpha", .value = .{ .string = "first" } },
        .{ .key = "beta", .value = .{ .string = "second" } },
    };
    const request: host.ToolCallRequestV1 = .{
        .tool_id = "generated/tooling@v1",
        .call_id = 1,
        .op_name = "echo",
        .arguments = .{ .object = fields[0..] },
    };
    var cloned = try request.clone(allocator);
    defer cloned.deinit(allocator);
}

fn cloneToolCallResult(allocator: std.mem.Allocator) !void {
    var items = [_]host.DataValueV1{
        .{ .string = "first" },
        .{ .string = "second" },
    };
    const result: host.ToolCallResultV1 = .{
        .tool_id = "generated/tooling@v1",
        .call_id = 1,
        .control = .@"resume",
        .value = .{ .array = items[0..] },
    };
    var cloned = try result.clone(allocator);
    defer cloned.deinit(allocator);
}

test "DataValueV1 clone unwinds partially cloned arrays on allocator failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneArrayPayload, .{});
}

test "DataValueV1 clone unwinds partially cloned objects on allocator failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneObjectPayload, .{});
}

test "ToolCallRequestV1 clone unwinds owned fields on allocator failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneToolCallRequest, .{});
}

test "ToolCallResultV1 clone unwinds owned fields on allocator failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneToolCallResult, .{});
}

test "HostAdapterV1 request, result, and failure deinit accept borrowed literals by default" {
    var request: host.ToolCallRequestV1 = .{
        .tool_id = "generated/tooling@v1",
        .call_id = 1,
        .op_name = "echo",
        .arguments = .{ .string = "hello" },
    };
    request.deinit(std.testing.allocator);

    var result: host.ToolCallResultV1 = .{
        .tool_id = "generated/tooling@v1",
        .call_id = 1,
        .control = .@"resume",
        .value = .{ .string = "world" },
    };
    result.deinit(std.testing.allocator);

    var failure: host.FailureV1 = .{
        .code = "provider_failure",
        .message = "backend unavailable",
    };
    failure.deinit(std.testing.allocator);
}

test "HostAdapterV1 borrowed payloads accept immutable bytes and container literals" {
    const array_items = [_]host.DataValueV1{
        .{ .bytes = "abc" },
        .{ .string = "nested" },
    };
    const object_fields = [_]host.ObjectFieldV1{
        .{
            .key = "payload",
            .value = .{ .array = array_items[0..] },
        },
    };
    var request: host.ToolCallRequestV1 = .{
        .tool_id = "generated/tooling@v1",
        .call_id = 3,
        .op_name = "echo",
        .arguments = .{ .object = object_fields[0..] },
    };
    request.deinit(std.testing.allocator);
}

test "HostAdapterV1 wrapper deinit accepts nested borrowed payloads when only container storage is owned" {
    var array_items = try std.testing.allocator.alloc(host.DataValueV1, 1);
    array_items[0] = .{ .string = "nested-borrowed" };
    var request: host.ToolCallRequestV1 = .{
        .tool_id = "generated/tooling@v1",
        .call_id = 1,
        .op_name = "echo",
        .arguments = .{ .array = array_items },
        .arguments_ownership = .container,
    };
    request.deinit(std.testing.allocator);

    var object_fields = try std.testing.allocator.alloc(host.ObjectFieldV1, 1);
    object_fields[0] = .{
        .key = "payload",
        .value = .{ .string = "nested-borrowed" },
    };
    var result: host.ToolCallResultV1 = .{
        .tool_id = "generated/tooling@v1",
        .call_id = 1,
        .control = .@"resume",
        .value = .{ .object = object_fields },
        .value_ownership = .container,
    };
    result.deinit(std.testing.allocator);
}

test "HostAdapterV1 dispatch accepts stateless adapters with null ctx" {
    const adapter: host.HostAdapterV1 = .{
        .ctx = null,
        .dispatchFn = struct {
            fn dispatch(ctx: ?*anyopaque, allocator: std.mem.Allocator, request: host.HostEffectRequestV1) anyerror!host.HostEffectResultV1 {
                try std.testing.expectEqual(@as(?*anyopaque, null), ctx);
                return .{
                    .request_id = request.request_id,
                    .body = .{ .success = .{
                        .tool_id = try allocator.dupe(u8, request.body.tool_call.tool_id),
                        .call_id = request.body.tool_call.call_id,
                        .control = .@"resume",
                        .value = .null,
                        .owns_tool_id = true,
                    } },
                };
            }
        }.dispatch,
    };

    var result = try adapter.dispatch(std.testing.allocator, .{
        .request_id = 7,
        .capability_id = 3,
        .op_id = 2,
        .body = .{ .tool_call = .{
            .tool_id = "generated/tooling@v1",
            .call_id = 7,
            .op_name = "echo",
            .arguments = .null,
        } },
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u64, 7), result.request_id);
    switch (result.body) {
        .success => |success| {
            try std.testing.expectEqualStrings("generated/tooling@v1", success.tool_id);
            try std.testing.expectEqual(@as(u64, 7), success.call_id);
            try std.testing.expectEqual(host.ToolControlV1.@"resume", success.control);
            switch (success.value) {
                .null => {},
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "HostAdapterV1 container ownership frees object keys for request and result wrappers" {
    var request_fields = try std.testing.allocator.alloc(host.ObjectFieldV1, 1);
    const request_key = try std.testing.allocator.dupe(u8, "request");
    errdefer std.testing.allocator.free(request_key);
    request_fields[0] = .{
        .key = request_key,
        .owns_key = true,
        .value = .{ .string = "nested-borrowed" },
    };
    var request: host.ToolCallRequestV1 = .{
        .tool_id = "generated/tooling@v1",
        .call_id = 2,
        .op_name = "echo",
        .arguments = .{ .object = request_fields },
        .arguments_ownership = .container,
    };
    request.deinit(std.testing.allocator);

    var result_fields = try std.testing.allocator.alloc(host.ObjectFieldV1, 1);
    const result_key = try std.testing.allocator.dupe(u8, "result");
    errdefer std.testing.allocator.free(result_key);
    result_fields[0] = .{
        .key = result_key,
        .owns_key = true,
        .value = .{ .string = "nested-borrowed" },
    };
    var result: host.ToolCallResultV1 = .{
        .tool_id = "generated/tooling@v1",
        .call_id = 2,
        .control = .@"resume",
        .value = .{ .object = result_fields },
        .value_ownership = .container,
    };
    result.deinit(std.testing.allocator);
}
