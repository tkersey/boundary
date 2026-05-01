/// Stable source-backed case id.
pub const source_case_id = "source.local_mutation_resume";
/// Embedded source text consumed by the source-validated source-backed checker.
pub const source = @embedFile("local_mutation_resume.zig");

/// Run the local-mutation case with source-backed control flow.
pub fn run(writer: anytype) anyerror!void {
    var local: i32 = 1;
    try writer.print("local={d}\n", .{local});
    const resumed: i32 = 41;
    try writer.print("resume={d}\n", .{resumed});
    local += resumed;
    try writer.print("local={d}\n", .{local});
    try writer.print("final={d}\n", .{local});
}
