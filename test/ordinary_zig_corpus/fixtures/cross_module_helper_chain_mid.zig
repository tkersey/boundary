const leaf = @import("cross_module_helper_chain_leaf.zig");

pub fn runHelper(writer: anytype) anyerror!i32 {
    return try leaf.runHelper(writer);
}
