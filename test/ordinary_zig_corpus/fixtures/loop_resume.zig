/// Stable ordinary-Zig case id.
pub const ordinary_case_id = "ordinary.loop_resume";

/// Run the loop case with ordinary Zig control flow.
pub fn run(writer: anytype) anyerror!void {
    var i: usize = 0;
    while (i < 2) : (i += 1) {
        try writer.print("loop={d}\n", .{i});
    }
    const resumed: i32 = 41;
    try writer.print("resume={d}\n", .{resumed});
    try writer.writeAll("loop=done\n");
    try writer.print("final={d}\n", .{resumed + 1});
}
