/// Stable ordinary-Zig case id.
pub const ordinary_case_id = "ordinary.helper_call_resume";
/// Embedded source text consumed by the source-validated ordinary lowerer.
pub const source = @embedFile("helper_call_resume.zig");

fn helper(writer: anytype) anyerror!i32 {
    try writer.writeAll("helper=enter\n");
    const resumed: i32 = 41;
    try writer.print("resume={d}\n", .{resumed});
    try writer.writeAll("helper=exit\n");
    return resumed + 1;
}

/// Run the helper-call case with ordinary Zig control flow.
pub fn run(writer: anytype) anyerror!void {
    const answer = try helper(writer);
    try writer.print("final={d}\n", .{answer});
}
