const shift = @import("shift");
const std = @import("std");

pub fn main() anyerror!void {
    var approved: usize = 0;
    for (0..200_000) |_| {
        if (std.mem.eql(u8, shift.generated.workflow.workflow("publish"), "completed")) approved += 1;
    }

    var stdout_buffer: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("approved={d}\n", .{approved});
    try stdout.flush();
}
