/// Stable ordinary-Zig case id.
pub const ordinary_case_id = "ordinary.cross_module_helper_resume";

const helper_mod = @import("cross_module_helper_leaf.zig");

/// Run the cross-module helper case with ordinary Zig control flow.
pub fn run(writer: anytype) anyerror!void {
    const answer = try helper_mod.runHelper(writer);
    try writer.print("final={d}\n", .{answer});
}
