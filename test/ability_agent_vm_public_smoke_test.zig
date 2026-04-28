const ability_agent_vm = @import("ability_agent_vm");
const fixture = @import("ability_agent_vm_fixture_spec.zig");
const std = @import("std");

test "build script exports the ability_agent_vm module from the retained source path" {
    const build_zig = try std.Io.Dir.cwd().readFileAlloc(
        std.Io.Threaded.global_single_threaded.io(),
        "build.zig",
        std.testing.allocator,
        .limited(1 << 20),
    );
    defer std.testing.allocator.free(build_zig);

    try std.testing.expect(std.mem.find(
        u8,
        build_zig,
        "b.addModule(\"ability_agent_vm\"",
    ) != null);
    try std.testing.expect(std.mem.find(
        u8,
        build_zig,
        ".root_source_file = b.path(\"src/ability_agent_vm.zig\")",
    ) != null);
}

const SeenRequest = struct {
    calls: usize = 0,
    saw_tell: bool = false,
    saw_smoke_payload: bool = false,
};

fn loadFixtureBytes(allocator: std.mem.Allocator) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(
        std.Io.Threaded.global_single_threaded.io(),
        fixture.artifact_path,
        allocator,
        .limited(1 << 20),
    );
}

test "ability_agent_vm public smoke executes artifact bytes through the supported runtime module" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator);
    defer allocator.free(bytes);

    var seen = SeenRequest{};
    const adapter: ability_agent_vm.host.Adapter = .{
        .ctx = &seen,
        .dispatchFn = struct {
            fn dispatch(
                ctx_ptr: ?*anyopaque,
                allocator_inner: std.mem.Allocator,
                request: ability_agent_vm.host.Request,
            ) anyerror!ability_agent_vm.host.Response {
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

    var result = try ability_agent_vm.runtime.runArtifact(allocator, bytes, adapter);
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

test "ability_agent_vm public smoke rejects mismatched success request ids" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator);
    defer allocator.free(bytes);

    var seen_calls: usize = 0;
    const adapter: ability_agent_vm.host.Adapter = .{
        .ctx = &seen_calls,
        .dispatchFn = struct {
            fn dispatch(
                ctx_ptr: ?*anyopaque,
                allocator_inner: std.mem.Allocator,
                request: ability_agent_vm.host.Request,
            ) anyerror!ability_agent_vm.host.Response {
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

    var result = try ability_agent_vm.runtime.runArtifact(allocator, bytes, adapter);
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

test "ability_agent_vm public options expose host-call budget failures" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator);
    defer allocator.free(bytes);

    const adapter: ability_agent_vm.host.Adapter = .{
        .ctx = null,
        .dispatchFn = struct {
            fn dispatch(
                _: ?*anyopaque,
                _: std.mem.Allocator,
                _: ability_agent_vm.host.Request,
            ) anyerror!ability_agent_vm.host.Response {
                return error.TestUnexpectedDispatch;
            }
        }.dispatch,
    };

    var result = try ability_agent_vm.runtime.runArtifactWithOptions(
        allocator,
        bytes,
        adapter,
        .{ .max_host_calls = 0 },
    );
    defer result.deinit(allocator);

    switch (result) {
        .failed => |failure| {
            try std.testing.expectEqualStrings("resource_exhausted", failure.failure.code);
            try std.testing.expectEqualStrings("artifact host-call budget exceeded", failure.failure.message);
            try std.testing.expectEqual(@as(usize, 0), failure.logs.len);
        },
        else => return error.TestUnexpectedRuntimeResult,
    }
}

test "ability_agent_vm public options bound response payload conversion" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator);
    defer allocator.free(bytes);

    const adapter: ability_agent_vm.host.Adapter = .{
        .ctx = null,
        .dispatchFn = struct {
            fn dispatch(
                _: ?*anyopaque,
                _: std.mem.Allocator,
                request: ability_agent_vm.host.Request,
            ) anyerror!ability_agent_vm.host.Response {
                return switch (request) {
                    .call => |tool_call| .{ .resumed = .{
                        .request_id = tool_call.request_id,
                        .tool_id = tool_call.tool_id,
                        .call_id = tool_call.request_id,
                        .value = .{ .string = "this payload is too large for the configured host bridge budget and should be rejected before runtime materialization" },
                    } },
                    else => return error.TestUnexpectedRequestKind,
                };
            }
        }.dispatch,
    };

    var result = try ability_agent_vm.runtime.runArtifactWithOptions(
        allocator,
        bytes,
        adapter,
        .{ .data_value_bounds = .{
            .max_depth = 4,
            .max_nodes = 8,
            .max_bytes = 80,
        } },
    );
    defer result.deinit(allocator);

    switch (result) {
        .failed => |failure| {
            try std.testing.expectEqualStrings("resource_exhausted", failure.failure.code);
            try std.testing.expectEqualStrings("artifact host payload budget exceeded", failure.failure.message);
            try std.testing.expectEqual(@as(usize, 1), failure.logs.len);
        },
        else => return error.TestUnexpectedRuntimeResult,
    }
}

test "ability_agent_vm public result conversion honors expanded data value bounds" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator);
    defer allocator.free(bytes);

    const large_message = try allocator.alloc(u8, (1 << 20) + 1);
    defer allocator.free(large_message);
    @memset(large_message, 'x');

    const FailureContext = struct {
        calls: usize = 0,
        message: []const u8,
    };
    var context: FailureContext = .{ .message = large_message };
    const adapter: ability_agent_vm.host.Adapter = .{
        .ctx = &context,
        .dispatchFn = struct {
            fn dispatch(
                ctx_ptr: ?*anyopaque,
                _: std.mem.Allocator,
                request: ability_agent_vm.host.Request,
            ) anyerror!ability_agent_vm.host.Response {
                const context_ptr: *FailureContext = @ptrCast(@alignCast(ctx_ptr.?));
                context_ptr.calls += 1;
                switch (request) {
                    .call => return .{ .failed = .{
                        .code = "provider_failure",
                        .message = context_ptr.message,
                    } },
                    else => return error.TestUnexpectedRequestKind,
                }
            }
        }.dispatch,
    };

    var result = try ability_agent_vm.runtime.runArtifactWithOptions(
        allocator,
        bytes,
        adapter,
        .{ .data_value_bounds = .{
            .max_depth = 8,
            .max_nodes = 16,
            .max_bytes = large_message.len + 1024,
        } },
    );
    defer result.deinit(allocator);

    switch (result) {
        .failed => |failure| {
            try std.testing.expectEqual(@as(usize, 1), context.calls);
            try std.testing.expectEqualStrings("provider_failure", failure.failure.code);
            try std.testing.expectEqual(large_message.len, failure.failure.message.len);
            try std.testing.expectEqual(@as(u8, 'x'), failure.failure.message[0]);
            try std.testing.expectEqual(@as(usize, 1), failure.logs.len);
            switch (failure.logs[0].response) {
                .failed => |logged| {
                    try std.testing.expectEqualStrings("provider_failure", logged.code);
                    try std.testing.expectEqual(large_message.len, logged.message.len);
                },
                else => return error.TestUnexpectedResponseKind,
            }
        },
        else => return error.TestUnexpectedRuntimeResult,
    }
}

test "ability_agent_vm public output snapshots carry explicit borrowed ownership" {
    const allocator = std.testing.allocator;
    const adapter: ability_agent_vm.host.Adapter = .{
        .ctx = null,
        .dispatchFn = struct {
            fn dispatch(
                _: ?*anyopaque,
                _: std.mem.Allocator,
                _: ability_agent_vm.host.Request,
            ) anyerror!ability_agent_vm.host.Response {
                return error.TestUnexpectedDispatch;
            }
        }.dispatch,
        .collectOutputSnapshotsFn = struct {
            fn collect(
                _: ?*anyopaque,
                allocator_inner: std.mem.Allocator,
                declared_outputs: []const ability_agent_vm.host.OutputDescriptor,
            ) anyerror![]ability_agent_vm.host.OutputSnapshot {
                try std.testing.expectEqual(@as(usize, 1), declared_outputs.len);
                const snapshots = try allocator_inner.alloc(ability_agent_vm.host.OutputSnapshot, 1);
                snapshots[0] = .{
                    .value = .{ .string = "borrowed" },
                    .value_ownership = .borrowed,
                };
                return snapshots;
            }
        }.collect,
    };
    const descriptors = [_]ability_agent_vm.host.OutputDescriptor{.{
        .label = "answer",
        .codec = .string,
    }};

    const snapshots = try adapter.collectOutputSnapshots(allocator, &descriptors);
    defer {
        for (snapshots) |*snapshot| snapshot.deinit(allocator);
        allocator.free(snapshots);
    }

    try std.testing.expectEqual(@as(usize, 1), snapshots.len);
    switch (snapshots[0].value) {
        .string => |value| try std.testing.expectEqualStrings("borrowed", value),
        else => return error.TestUnexpectedOutputSnapshot,
    }
}
