fn helper(
    one: []const u8,
    _two: []const u8,
    _three: []const u8,
    _four: []const u8,
    _five: []const u8,
    _six: []const u8,
    _seven: []const u8,
    eight: []const u8,
    eff: anytype,
) !void {
    try eff.writer.tell(one);
    try eff.writer.tell(eight);
}

/// Helper body used to prove max-arity helper calls keep enough lowering scratch space.
pub fn runBody(eff: anytype) ![]const u8 {
    try helper("a", "b", "c", "d", "e", "f", "g", "h", eff);
    return "done";
}
