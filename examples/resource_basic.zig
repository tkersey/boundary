const lowered_runtime = @import("private_lowered_runtime");
const std = @import("std");

/// Write the resource-effect transcript through the lowered runtime seam.
pub fn run(writer: anytype) anyerror!void {
    _ = try lowered_runtime.runCaseId(writer, "resource_basic");
}

/// Run the resource-effect example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
