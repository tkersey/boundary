const job_workflow = @import("workflow.zig");
const std = @import("std");

/// Run the advanced job-workflow showcase.
pub fn main() anyerror!void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try job_workflow.runShowcase(stdout);
    try stdout.flush();
}
