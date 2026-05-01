/// Stable source-backed case id.
pub const source_case_id = "source.loop_resume";
/// Embedded source text consumed by the source-validated source-backed checker.
pub const source = @embedFile("loop_resume.zig");

/// Run the loop case with source-backed control flow.
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
