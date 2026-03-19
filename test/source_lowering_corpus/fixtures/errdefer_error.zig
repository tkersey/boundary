const std = @import("std");

/// Stable source-lowering case id.
pub const source_case_id = "source.errdefer_error";
/// Embedded source text consumed by the source-validated source-lowering checker.
pub const source = @embedFile("errdefer_error.zig");

fn writeCleanup(writer: anytype, line: []const u8) void {
    writer.writeAll(line) catch |err| std.debug.panic("cleanup write failed: {s}", .{@errorName(err)});
}

fn body(writer: anytype) anyerror!void {
    errdefer writeCleanup(writer, "errdefer=cleanup\n");
    try writer.writeAll("body=enter\n");
    return error.Boom;
}

/// Run the errdefer case with source-lowering control flow.
pub fn run(writer: anytype) anyerror!void {
    body(writer) catch |err| switch (err) {
        error.Boom => {
            try writer.writeAll("error=boom\n");
            try writer.writeAll("final=error=boom\n");
            return;
        },
        else => return err,
    };
    unreachable;
}
