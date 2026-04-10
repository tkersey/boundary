const example = @import("example_open_row_state_writer");
const shift_compile = @import("shift_compile");
const shift_vm = @import("shift_vm");
const std = @import("std");

const RuntimeContext = struct {
    state: i32,
    writer_items: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (self.writer_items.items) |item| allocator.free(item);
        self.writer_items.deinit(allocator);
    }
};

fn dispatch(ctx: ?*anyopaque, allocator: std.mem.Allocator, request: shift_vm.host_adapter.HostEffectRequestV1) anyerror!shift_vm.host_adapter.HostEffectResultV1 {
    const runtime_ctx: *RuntimeContext = @ptrCast(@alignCast(ctx.?));
    const tool_call = request.body.tool_call;
    if (std.mem.eql(u8, tool_call.op_name, "afterGet") or
        std.mem.eql(u8, tool_call.op_name, "afterSet") or
        std.mem.eql(u8, tool_call.op_name, "afterTell"))
    {
        return .{
            .request_id = request.request_id,
            .body = .{ .success = .{
                .tool_id = try allocator.dupe(u8, tool_call.tool_id),
                .call_id = tool_call.call_id,
                .control = .@"resume",
                .value = try tool_call.arguments.clone(allocator),
                .owns_tool_id = true,
                .value_ownership = .deep,
            } },
        };
    }
    if (std.mem.eql(u8, tool_call.op_name, "get")) {
        return .{
            .request_id = request.request_id,
            .body = .{ .success = .{
                .tool_id = try allocator.dupe(u8, tool_call.tool_id),
                .call_id = tool_call.call_id,
                .control = .@"resume",
                .value = .{ .i64 = runtime_ctx.state },
                .owns_tool_id = true,
            } },
        };
    }
    if (std.mem.eql(u8, tool_call.op_name, "set")) {
        runtime_ctx.state = @intCast(tool_call.arguments.i64);
        return .{
            .request_id = request.request_id,
            .body = .{ .success = .{
                .tool_id = try allocator.dupe(u8, tool_call.tool_id),
                .call_id = tool_call.call_id,
                .control = .@"resume",
                .value = .null,
                .owns_tool_id = true,
            } },
        };
    }
    if (std.mem.eql(u8, tool_call.op_name, "tell")) {
        try runtime_ctx.writer_items.append(allocator, try allocator.dupe(u8, tool_call.arguments.string));
        return .{
            .request_id = request.request_id,
            .body = .{ .success = .{
                .tool_id = try allocator.dupe(u8, tool_call.tool_id),
                .call_id = tool_call.call_id,
                .control = .@"resume",
                .value = .null,
                .owns_tool_id = true,
            } },
        };
    }
    return .{
        .request_id = request.request_id,
        .body = .{ .failed = .{
            .code = try allocator.dupe(u8, "unknown_op"),
            .message = try allocator.dupe(u8, tool_call.op_name),
            .owns_code = true,
            .owns_message = true,
        } },
    };
}

/// Execute the retained state/writer example through the ArtifactV1 runtime and print the transcript summary.
pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const bytes = try shift_compile.compileAndEncode(
        allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "artifact-vm-wasm-parity",
            .capabilities = &.{},
        },
    );

    var context = RuntimeContext{ .state = 5 };
    defer context.deinit(allocator);

    var result = try shift_vm.runtime.runArtifact(allocator, bytes, .{
        .ctx = &context,
        .dispatchFn = dispatch,
    });
    defer result.deinit(allocator);

    const completed = switch (result) {
        .completed => |*completed| completed,
        .rejected => |failure| {
            std.debug.print("host rejected request: {s}: {s}\n", .{ failure.failure.code, failure.failure.message });
            return error.UnexpectedHostRejection;
        },
        .failed => |failure| {
            std.debug.print("host failed request: {s}: {s}\n", .{ failure.failure.code, failure.failure.message });
            return error.UnexpectedHostFailure;
        },
    };

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    for (context.writer_items.items) |item| {
        try stdout.print("item={s}\n", .{item});
    }
    try stdout.print("final_state={d}\n", .{context.state});
    try stdout.print("value={s}\n", .{completed.value.string});
    try stdout.print("requests={d}\n", .{completed.logs.len});
    try stdout.flush();
}
