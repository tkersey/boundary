/// Emit one writer event for the public runtime smoke fixture.
fn emitSmoke(eff: anytype) !void {
    try eff.writer.tell("smoke");
}

/// Run one tiny writer-only smoke workflow through the public compile path.
pub fn runBody(eff: anytype) ![]const u8 {
    try emitSmoke(eff);
    return "done";
}
