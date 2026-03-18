/// Stable source-lowering case id.
pub const source_case_id = "source.nested_prompt_static_redelim";
/// Embedded source text consumed by the source-validated source-lowering checker.
pub const source = @embedFile("nested_prompt_static_redelim.zig");

fn inner(writer: anytype) anyerror!i32 {
    try writer.writeAll("inner=enter\n");
    try writer.writeAll("inner=exit\n");
    return 7;
}

fn outer(writer: anytype) anyerror!i32 {
    try writer.writeAll("outer=enter\n");
    const inner_value = try inner(writer);
    try writer.writeAll("outer=exit\n");
    return inner_value + 5;
}

/// Run the nested static re-delimitation case with source-lowering control flow.
pub fn run(writer: anytype) anyerror!void {
    const answer = try outer(writer);
    try writer.print("final={d}\n", .{answer});
}
