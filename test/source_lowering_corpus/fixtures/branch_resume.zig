/// Stable source-lowering case id.
pub const source_case_id = "source.branch_resume";
/// Embedded source text consumed by the source-validated source-lowering checker.
pub const source = @embedFile("branch_resume.zig");

/// Run the branch case with source-lowering control flow.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll("branch=before\n");
    var answer: i32 = 0;
    const take_branch = true;
    if (take_branch) {
        try writer.writeAll("branch=taken\n");
        const resumed: i32 = 41;
        try writer.print("resume={d}\n", .{resumed});
        answer = resumed + 1;
    }
    try writer.writeAll("branch=after\n");
    try writer.print("final={d}\n", .{answer});
}
