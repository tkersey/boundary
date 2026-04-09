const host = @import("shift_vm").host_adapter;
const std = @import("std");

pub fn assertSequentialRequestIds(entries: []const host.HostLogEntryV1) !void {
    for (entries, 0..) |entry, index| {
        try std.testing.expectEqual(@as(u64, index + 1), entry.request.request_id);
        try std.testing.expectEqual(entry.request.request_id, entry.result.request_id);
    }
}

pub fn assertToolCallShape(entry: host.HostLogEntryV1, tool_id: []const u8, op_name: []const u8) !void {
    const request = entry.request.body.tool_call;
    try std.testing.expectEqualStrings(tool_id, request.tool_id);
    try std.testing.expectEqualStrings(op_name, request.op_name);
    const result = entry.result.body.ok;
    try std.testing.expectEqualStrings(tool_id, result.tool_id);
    try std.testing.expectEqual(request.call_id, result.call_id);
}
