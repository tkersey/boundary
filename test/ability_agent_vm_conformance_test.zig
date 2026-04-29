const ability_agent_vm = @import("ability_agent_vm");
const fixture_options = @import("agent_vm_conformance_fixture_options");
const std = @import("std");

const conformance_options: ability_agent_vm.runtime.RunOptions = .{
    .max_artifact_bytes = 16 * 1024 * 1024,
    .max_host_calls = 0,
    .max_log_entries = 0,
    .max_log_bytes = 0,
    .data_value_bounds = .{
        .max_depth = 64,
        .max_nodes = 4096,
        .max_bytes = 1 << 20,
    },
};

const OutputValueContext = struct {
    dispatch_calls: usize = 0,
    value: ability_agent_vm.host.DataValue,
};

fn loadFixtureBytes(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(
        std.Io.Threaded.global_single_threaded.io(),
        path,
        allocator,
        .limited(conformance_options.max_artifact_bytes + 1),
    );
}

fn noDispatchAdapter() ability_agent_vm.host.Adapter {
    return .{
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
}

fn outputAdapter(ctx: *OutputValueContext) ability_agent_vm.host.Adapter {
    return .{
        .ctx = ctx,
        .dispatchFn = struct {
            fn dispatch(
                ctx_ptr: ?*anyopaque,
                _: std.mem.Allocator,
                _: ability_agent_vm.host.Request,
            ) anyerror!ability_agent_vm.host.Response {
                const output_ctx: *OutputValueContext = @ptrCast(@alignCast(ctx_ptr.?));
                output_ctx.dispatch_calls += 1;
                return error.TestUnexpectedDispatch;
            }
        }.dispatch,
        .collectOutputSnapshotsFn = struct {
            fn collect(
                ctx_ptr: ?*anyopaque,
                allocator: std.mem.Allocator,
                declared_outputs: []const ability_agent_vm.host.OutputDescriptor,
            ) anyerror![]ability_agent_vm.host.OutputSnapshot {
                const output_ctx: *OutputValueContext = @ptrCast(@alignCast(ctx_ptr.?));
                try std.testing.expectEqual(@as(usize, 1), declared_outputs.len);
                const snapshots = try allocator.alloc(ability_agent_vm.host.OutputSnapshot, 1);
                snapshots[0] = .{
                    .label = declared_outputs[0].label,
                    .value = output_ctx.value,
                };
                return snapshots;
            }
        }.collect,
    };
}

fn expectOutputBudgetFailure(result: ability_agent_vm.runtime.RunArtifactResult) !void {
    switch (result) {
        .failed => |failure| {
            try std.testing.expectEqualStrings("resource_exhausted", failure.failure.code);
            try std.testing.expectEqualStrings("artifact output snapshot payload budget exceeded", failure.failure.message);
            try std.testing.expectEqual(@as(usize, 0), failure.logs.len);
        },
        else => return error.TestUnexpectedRuntimeResult,
    }
}

test "ability_agent_vm conformance fixed profile accepts no-host artifacts" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator, fixture_options.no_host_artifact_path);
    defer allocator.free(bytes);

    var result = try ability_agent_vm.runtime.runArtifactWithOptions(
        allocator,
        bytes,
        noDispatchAdapter(),
        conformance_options,
    );
    defer result.deinit(allocator);

    switch (result) {
        .completed => |completed| {
            switch (completed.value) {
                .string => |value| try std.testing.expectEqualStrings("ok", value),
                else => return error.TestUnexpectedResult,
            }
            try std.testing.expectEqual(@as(usize, 0), completed.outputs.len);
            try std.testing.expectEqual(@as(usize, 0), completed.logs.len);
        },
        else => return error.TestUnexpectedRuntimeResult,
    }
}

test "ability_agent_vm conformance rejects host calls before dispatch" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator, fixture_options.host_call_artifact_path);
    defer allocator.free(bytes);

    var dispatch_calls: usize = 0;
    const adapter: ability_agent_vm.host.Adapter = .{
        .ctx = &dispatch_calls,
        .dispatchFn = struct {
            fn dispatch(
                ctx_ptr: ?*anyopaque,
                _: std.mem.Allocator,
                _: ability_agent_vm.host.Request,
            ) anyerror!ability_agent_vm.host.Response {
                const counter: *usize = @ptrCast(@alignCast(ctx_ptr.?));
                counter.* += 1;
                return error.TestUnexpectedDispatch;
            }
        }.dispatch,
    };

    var result = try ability_agent_vm.runtime.runArtifactWithOptions(
        allocator,
        bytes,
        adapter,
        conformance_options,
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
    try std.testing.expectEqual(@as(usize, 0), dispatch_calls);
}

test "ability_agent_vm conformance bounds completed value bytes" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator, fixture_options.oversized_return_artifact_path);
    defer allocator.free(bytes);

    var result = try ability_agent_vm.runtime.runArtifactWithOptions(
        allocator,
        bytes,
        noDispatchAdapter(),
        conformance_options,
    );
    defer result.deinit(allocator);

    switch (result) {
        .failed => |failure| {
            try std.testing.expectEqualStrings("resource_exhausted", failure.failure.code);
            try std.testing.expectEqualStrings("artifact completed value payload budget exceeded", failure.failure.message);
            try std.testing.expectEqual(@as(usize, 0), failure.logs.len);
        },
        else => return error.TestUnexpectedRuntimeResult,
    }
}

test "ability_agent_vm conformance bounds output snapshot depth" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator, fixture_options.output_snapshot_artifact_path);
    defer allocator.free(bytes);

    const depth = conformance_options.data_value_bounds.max_depth + 2;
    const levels = try allocator.alloc([]ability_agent_vm.host.DataValue, depth);
    defer allocator.free(levels);
    for (levels) |*level| level.* = try allocator.alloc(ability_agent_vm.host.DataValue, 1);
    defer for (levels) |level| allocator.free(level);
    for (levels[0 .. depth - 1], 0..) |level, index| {
        level[0] = .{ .array = levels[index + 1] };
    }
    levels[depth - 1][0] = .null;

    var ctx: OutputValueContext = .{ .value = .{ .array = levels[0] } };
    var result = try ability_agent_vm.runtime.runArtifactWithOptions(
        allocator,
        bytes,
        outputAdapter(&ctx),
        conformance_options,
    );
    defer result.deinit(allocator);

    try expectOutputBudgetFailure(result);
    try std.testing.expectEqual(@as(usize, 0), ctx.dispatch_calls);
}

test "ability_agent_vm conformance bounds output snapshot nodes" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator, fixture_options.output_snapshot_artifact_path);
    defer allocator.free(bytes);

    const item_count = conformance_options.data_value_bounds.max_nodes + 1;
    const items = try allocator.alloc(ability_agent_vm.host.DataValue, item_count);
    defer allocator.free(items);
    for (items) |*item| item.* = .null;

    var ctx: OutputValueContext = .{ .value = .{ .array = items } };
    var result = try ability_agent_vm.runtime.runArtifactWithOptions(
        allocator,
        bytes,
        outputAdapter(&ctx),
        conformance_options,
    );
    defer result.deinit(allocator);

    try expectOutputBudgetFailure(result);
    try std.testing.expectEqual(@as(usize, 0), ctx.dispatch_calls);
}

test "ability_agent_vm conformance bounds output snapshot bytes" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator, fixture_options.output_snapshot_artifact_path);
    defer allocator.free(bytes);

    const payload = try allocator.alloc(u8, conformance_options.data_value_bounds.max_bytes + 1);
    defer allocator.free(payload);
    @memset(payload, 'x');
    const values = [_]ability_agent_vm.host.DataValue{.{ .string = payload }};

    var ctx: OutputValueContext = .{ .value = .{ .array = &values } };
    var result = try ability_agent_vm.runtime.runArtifactWithOptions(
        allocator,
        bytes,
        outputAdapter(&ctx),
        conformance_options,
    );
    defer result.deinit(allocator);

    try expectOutputBudgetFailure(result);
    try std.testing.expectEqual(@as(usize, 0), ctx.dispatch_calls);
}
