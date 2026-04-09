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
                } },
            },
            .result = .{
                .request_id = 1,
                .body = .{ .success = .{
                    .tool_id = try std.testing.allocator.dupe(u8, "generated/tooling@v1"),
                    .call_id = 1,
                    .control = .@"resume",
                    .value = .null,
                } },
            },
        },
    };
    defer for (&entries) |*entry| entry.deinit(std.testing.allocator);

    try conformance.assertSequentialRequestIds(&entries);
    try conformance.assertToolCallShape(entries[0], "generated/tooling@v1", "tell");
}
