/// Stable source-lowering case id.
pub const source_case_id = "source.helper_call_resume";
/// Embedded source text consumed by the source-validated source-lowering checker.
pub const source = @embedFile("helper_call_resume.zig");

fn helper(writer: anytype) anyerror!i32 {
    try writer.writeAll("helper=enter\n");
    const resumed: i32 = 41;
    try writer.print("resume={d}\n", .{resumed});
    try writer.writeAll("helper=exit\n");
    return resumed + 1;
}

/// Run the helper-call case with source-lowering control flow.
pub fn run(writer: anytype) anyerror!void {
    const answer = try helper(writer);
    try writer.print("final={d}\n", .{answer});
}
