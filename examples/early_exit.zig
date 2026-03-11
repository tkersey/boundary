const std = @import("std");
const witnesses = @import("witnesses");

/// Run the early-exit witness example.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try witnesses.runEarlyExit(stdout);
    try stdout.flush();
}
