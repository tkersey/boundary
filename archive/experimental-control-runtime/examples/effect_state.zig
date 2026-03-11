const control_lab = @import("control_lab_scenarios");
const std = @import("std");

/// Run the state example.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try control_lab.runTerminalCancel(stdout);
    try stdout.flush();
}
