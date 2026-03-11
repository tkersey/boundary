const shift = @import("shift");
const std = @import("std");

pub fn main() anyerror!void {
    var sum: i64 = 0;
    for (0..200_000) |_| sum += shift.generated.basic_resume.basicResume();

    var stdout_buffer: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("sum={d}\n", .{sum});
    try stdout.flush();
}
