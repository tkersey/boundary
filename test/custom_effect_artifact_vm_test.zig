const ability_agent_vm = @import("ability_agent_vm");
const std = @import("std");

const custom_approval_artifact_path = "test/fixtures/custom_approval_workflow.artifact";

const ExpectedTranscript = struct {
    lookups: usize,
    choices: usize,
    continuations: usize,
    aborts: usize,
    last_lookup: []const u8,
    last_choice: []const u8,
    last_abort: []const u8,
};

fn expectTranscript(actual: ExpectedTranscript, expected: ExpectedTranscript) !void {
    try std.testing.expectEqual(expected.lookups, actual.lookups);
    try std.testing.expectEqual(expected.choices, actual.choices);
    try std.testing.expectEqual(expected.continuations, actual.continuations);
    try std.testing.expectEqual(expected.aborts, actual.aborts);
    try std.testing.expectEqualStrings(expected.last_lookup, actual.last_lookup);
    try std.testing.expectEqualStrings(expected.last_choice, actual.last_choice);
    try std.testing.expectEqualStrings(expected.last_abort, actual.last_abort);
}

const DirectBranch = enum { approve, deny };

const ArtifactContext = struct {
    exists_value: bool,
    branch: DirectBranch,
    transcript: ExpectedTranscript = .{
        .lookups = 0,
        .choices = 0,
        .continuations = 0,
        .aborts = 0,
        .last_lookup = "",
        .last_choice = "",
        .last_abort = "",
    },
};

fn responseCallId(request: *const ability_agent_vm.host.Request) u64 {
    return switch (request.*) {
        .call => |call| call.request_id,
        .after_call => |after_call| after_call.call_id,
    };
}

fn requestId(request: *const ability_agent_vm.host.Request) u64 {
    return switch (request.*) {
        .call => |call| call.request_id,
        .after_call => |after_call| after_call.request_id,
    };
}

fn toolId(request: *const ability_agent_vm.host.Request) []const u8 {
    return switch (request.*) {
        .call => |call| call.tool_id,
        .after_call => |after_call| after_call.tool_id,
    };
}

fn resumedResponse(
    request: *const ability_agent_vm.host.Request,
    value: ability_agent_vm.host.DataValue,
) ability_agent_vm.host.Response {
    return .{ .resumed = .{
        .request_id = requestId(request),
        .tool_id = toolId(request),
        .call_id = responseCallId(request),
        .value = value,
    } };
}

fn terminalResponse(
    request: *const ability_agent_vm.host.Request,
    comptime tag: enum { aborted, return_now },
    value: ability_agent_vm.host.DataValue,
) ability_agent_vm.host.Response {
    const payload: ability_agent_vm.host.Terminal = .{
        .request_id = requestId(request),
        .tool_id = toolId(request),
        .call_id = responseCallId(request),
        .value = value,
    };
    return switch (tag) {
        .aborted => .{ .aborted = payload },
        .return_now => .{ .return_now = payload },
    };
}

fn approvalArtifactAdapter(ctx: *ArtifactContext) ability_agent_vm.host.Adapter {
    return .{
        .ctx = ctx,
        .dispatchFn = struct {
            fn dispatch(
                ctx_ptr: ?*anyopaque,
                _: std.mem.Allocator,
                request: *const ability_agent_vm.host.Request,
            ) anyerror!ability_agent_vm.host.Response {
                const artifact_ctx: *ArtifactContext = @ptrCast(@alignCast(ctx_ptr.?));
                switch (request.*) {
                    .call => |call| {
                        if (std.mem.eql(u8, call.op_name, "exists")) {
                            artifact_ctx.transcript.lookups += 1;
                            const payload = switch (call.arguments) {
                                .string => |value| value,
                                else => return error.TestUnexpectedPayload,
                            };
                            artifact_ctx.transcript.last_lookup = if (std.mem.eql(u8, payload, "publish-7"))
                                "publish-7"
                            else if (std.mem.eql(u8, payload, "request-7"))
                                "request-7"
                            else
                                return error.TestUnexpectedPayload;
                            return resumedResponse(request, .{ .bool = artifact_ctx.exists_value });
                        }
                        if (std.mem.eql(u8, call.op_name, "request")) {
                            artifact_ctx.transcript.choices += 1;
                            const payload = switch (call.arguments) {
                                .string => |value| value,
                                else => return error.TestUnexpectedPayload,
                            };
                            if (!std.mem.eql(u8, payload, "request-7")) return error.TestUnexpectedPayload;
                            artifact_ctx.transcript.last_choice = "request-7";
                            return switch (artifact_ctx.branch) {
                                .approve => resumedResponse(request, .{ .string = "approved" }),
                                .deny => terminalResponse(request, .return_now, .{ .string = "denied" }),
                            };
                        }
                        if (std.mem.eql(u8, call.op_name, "invalid")) {
                            artifact_ctx.transcript.aborts += 1;
                            const payload = switch (call.arguments) {
                                .string => |value| value,
                                else => return error.TestUnexpectedPayload,
                            };
                            if (!std.mem.eql(u8, payload, "missing")) return error.TestUnexpectedPayload;
                            artifact_ctx.transcript.last_abort = "missing";
                            return terminalResponse(request, .aborted, .{ .string = "invalid:missing" });
                        }
                        return error.TestUnexpectedDispatch;
                    },
                    .after_call => |after_call| {
                        if (!std.mem.eql(u8, after_call.op_name, "afterRequest")) return error.TestUnexpectedDispatch;
                        artifact_ctx.transcript.continuations += 1;
                        return resumedResponse(request, after_call.answer);
                    },
                }
            }
        }.dispatch,
    };
}

fn runArtifactWorkflowCase(
    allocator: std.mem.Allocator,
    artifact_bytes: []const u8,
    exists_value: bool,
    branch: DirectBranch,
) anyerror!struct {
    value: []const u8,
    transcript: ExpectedTranscript,
    logs_len: usize,
} {
    var ctx = ArtifactContext{
        .exists_value = exists_value,
        .branch = branch,
    };
    var result = try ability_agent_vm.runtime.runArtifact(
        allocator,
        artifact_bytes,
        approvalArtifactAdapter(&ctx),
    );
    defer result.deinit(allocator);
    return switch (result) {
        .completed => |completed| completed_result: {
            const value = switch (completed.value) {
                .string => |value| value,
                else => return error.TestUnexpectedResult,
            };
            break :completed_result .{
                .value = try allocator.dupe(u8, value),
                .transcript = ctx.transcript,
                .logs_len = completed.logs.len,
            };
        },
        else => error.TestUnexpectedRuntimeResult,
    };
}

fn loadFixtureBytes(allocator: std.mem.Allocator) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(
        std.Io.Threaded.global_single_threaded.io(),
        custom_approval_artifact_path,
        allocator,
        .limited(1 << 20),
    );
}

test "custom approval workflow ArtifactV1 round-trips and executes approve deny invalid branches" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator);
    defer allocator.free(bytes);

    const approved = try runArtifactWorkflowCase(allocator, bytes, true, .approve);
    defer allocator.free(approved.value);
    try std.testing.expectEqualStrings("published:approved", approved.value);
    try expectTranscript(approved.transcript, .{
        .lookups = 2,
        .choices = 1,
        .continuations = 1,
        .aborts = 0,
        .last_lookup = "publish-7",
        .last_choice = "request-7",
        .last_abort = "",
    });
    try std.testing.expectEqual(@as(usize, 4), approved.logs_len);

    const denied = try runArtifactWorkflowCase(allocator, bytes, true, .deny);
    defer allocator.free(denied.value);
    try std.testing.expectEqualStrings("denied", denied.value);
    try expectTranscript(denied.transcript, .{
        .lookups = 1,
        .choices = 1,
        .continuations = 0,
        .aborts = 0,
        .last_lookup = "request-7",
        .last_choice = "request-7",
        .last_abort = "",
    });
    try std.testing.expectEqual(@as(usize, 2), denied.logs_len);

    const invalid = try runArtifactWorkflowCase(allocator, bytes, false, .approve);
    defer allocator.free(invalid.value);
    try std.testing.expectEqualStrings("invalid:missing", invalid.value);
    try expectTranscript(invalid.transcript, .{
        .lookups = 1,
        .choices = 0,
        .continuations = 0,
        .aborts = 1,
        .last_lookup = "request-7",
        .last_choice = "",
        .last_abort = "missing",
    });
    try std.testing.expectEqual(@as(usize, 2), invalid.logs_len);
}
