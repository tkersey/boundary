/// Stable ordinary-Zig case id.
pub const ordinary_case_id = "ordinary.cross_module_helper_chain_resume";

const mid_mod = @import("cross_module_helper_chain_mid.zig");

/// Run the cross-module helper-chain case with ordinary Zig control flow.
pub fn run(writer: anytype) anyerror!void {
    const answer = try mid_mod.runHelper(writer);
    try writer.print("final={d}\n", .{answer});
}
