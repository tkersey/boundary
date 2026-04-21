const shift_agent_vm = @import("shift_agent_vm");
const std = @import("std");
const fixture_artifact_path = "test/fixtures/shift_agent_vm_smoke.artifact";

const SeenRequest = struct {
    calls: usize = 0,
    saw_tell: bool = false,
    saw_smoke_payload: bool = false,
};

fn loadFixtureBytes(allocator: std.mem.Allocator) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(
        std.Io.Threaded.global_single_threaded.io(),
        fixture_artifact_path,
        allocator,
        .limited(1 << 20),
    );
}

test "shift_agent_vm public smoke executes artifact bytes through the supported runtime module" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator);
    defer allocator.free(bytes);

    var seen = SeenRequest{};
    const adapter: shift_agent_vm.host.Adapter = .{
        .ctx = &seen,
        .dispatchFn = struct {
            fn dispatch(
                ctx_ptr: ?*anyopaque,
                allocator_inner: std.mem.Allocator,
                request: shift_agent_vm.host.Request,
            ) anyerror!shift_agent_vm.host.Response {
                const seen_ptr: *SeenRequest = @ptrCast(@alignCast(ctx_ptr.?));
                switch (request) {
                    .call => |tool_call| {
                        seen_ptr.calls += 1;
                        seen_ptr.saw_tell = std.mem.eql(u8, tool_call.op_name, "tell");
                        seen_ptr.saw_smoke_payload = switch (tool_call.arguments) {
                            .string => |value| std.mem.eql(u8, value, "smoke"),
                            else => return error.TestUnexpectedPayload,
                        };
                        return .{ .resumed = .{
                            .request_id = tool_call.request_id,
                            .tool_id = try allocator_inner.dupe(u8, tool_call.tool_id),
                            .call_id = tool_call.request_id,
                            .value = .null,
                            .owns_tool_id = true,
                        } };
                    },
                    else => return error.TestUnexpectedRequestKind,
                }
            }
        }.dispatch,
    };

    var result = try shift_agent_vm.runtime.runArtifact(allocator, bytes, adapter);
    defer result.deinit(allocator);

    switch (result) {
        .completed => |completed| {
            try std.testing.expectEqual(@as(usize, 1), seen.calls);
            try std.testing.expect(seen.saw_tell);
            try std.testing.expect(seen.saw_smoke_payload);
            switch (completed.value) {
                .string => |value| try std.testing.expectEqualStrings("done", value),
                else => return error.TestUnexpectedResult,
            }
            try std.testing.expectEqual(@as(usize, 0), completed.outputs.len);
            try std.testing.expectEqual(@as(usize, 1), completed.logs.len);
            switch (completed.logs[0].request) {
                .call => |request| {
                    try std.testing.expectEqual(@as(u64, 1), request.request_id);
                    try std.testing.expectEqualStrings("tell", request.op_name);
                },
                else => return error.TestUnexpectedRequestKind,
            }
            switch (completed.logs[0].response) {
                .resumed => |response| {
                    try std.testing.expectEqual(@as(u64, 1), response.request_id);
                    try std.testing.expectEqualStrings("generated/writer@v1", response.tool_id);
                },
                else => return error.TestUnexpectedResponseKind,
            }
        },
        else => return error.TestUnexpectedRuntimeResult,
    }
}

test "shift_agent_vm public smoke rejects mismatched success request ids" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator);
    defer allocator.free(bytes);

    var seen_calls: usize = 0;
    const adapter: shift_agent_vm.host.Adapter = .{
        .ctx = &seen_calls,
        .dispatchFn = struct {
            fn dispatch(
                ctx_ptr: ?*anyopaque,
                allocator_inner: std.mem.Allocator,
                request: shift_agent_vm.host.Request,
            ) anyerror!shift_agent_vm.host.Response {
                const seen_calls_ptr: *usize = @ptrCast(@alignCast(ctx_ptr.?));
                switch (request) {
                    .call => |tool_call| {
                        seen_calls_ptr.* += 1;
                        return .{ .resumed = .{
                            .request_id = tool_call.request_id + 1,
                            .tool_id = try allocator_inner.dupe(u8, tool_call.tool_id),
                            .call_id = tool_call.request_id,
                            .value = .null,
                            .owns_tool_id = true,
                        } };
                    },
                    else => return error.TestUnexpectedRequestKind,
                }
            }
        }.dispatch,
    };

    var result = try shift_agent_vm.runtime.runArtifact(allocator, bytes, adapter);
    defer result.deinit(allocator);

    switch (result) {
        .failed => |failure| {
            try std.testing.expectEqual(@as(usize, 1), seen_calls);
            try std.testing.expectEqualStrings("invalid_host_reply", failure.failure.code);
            try std.testing.expectEqualStrings("host reply request_id must echo the request", failure.failure.message);
            try std.testing.expectEqual(@as(usize, 1), failure.logs.len);
        },
        else => return error.TestUnexpectedRuntimeResult,
    }
}
