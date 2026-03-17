const std = @import("std");

/// Stable ordinary-Zig case id.
pub const ordinary_case_id = "ordinary.defer_resume";
/// Embedded source text consumed by the source-validated ordinary lowerer.
pub const source = @embedFile("defer_resume.zig");

fn writeCleanup(writer: anytype, line: []const u8) void {
    writer.writeAll(line) catch |err| std.debug.panic("cleanup write failed: {s}", .{@errorName(err)});
}

fn body(writer: anytype) anyerror!i32 {
    defer writeCleanup(writer, "defer=cleanup\n");
    try writer.writeAll("body=enter\n");
    const resumed: i32 = 41;
    try writer.print("resume={d}\n", .{resumed});
    return resumed + 1;
}

/// Run the defer case with ordinary Zig control flow.
pub fn run(writer: anytype) anyerror!void {
    const answer = try body(writer);
    try writer.print("final={d}\n", .{answer});
}
