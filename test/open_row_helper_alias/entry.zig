const a_helpers = @import("a_helpers.zig");
const b_helpers = @import("b_helpers.zig");

/// Call both imported helper modules so alias-based lowering must preserve module identity.
pub fn runBody(eff: anytype) anyerror!void {
    try a_helpers.helper(eff);
    try b_helpers.helper(eff);
}
