const shift = @import("shift");
const std = @import("std");

pub fn main() anyerror!void {
    const result = shift.generated.workflow.workflow("publish");

    var stdout_buffer: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("result={s}\n", .{result});
    try stdout.flush();
}
