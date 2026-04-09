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
                    .owns_arguments = true,
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
