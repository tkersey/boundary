/// Helper body used to prove explicit-path lowering ignores ordinary line comments.
fn helper(eff: anytype) !void {
    // This comment should not change the retained helper-body lowering result.
    try eff.writer.tell("commented");
}

/// Entry body used to prove helper-body comments do not break explicit-path lowering.
pub fn runBody(eff: anytype) ![]const u8 {
    try helper(eff);
    return "done";
}
