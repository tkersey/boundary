const std = @import("std");
const witnesses = @import("witnesses");

/// Run the deferred nested-workflow example outside the active practical witness set.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try witnesses.runNestedWorkflow(stdout);
    try stdout.flush();
}
