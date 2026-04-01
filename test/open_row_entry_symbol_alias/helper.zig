/// Helper function that intentionally collides with the entry symbol name.
pub fn runBody(eff: anytype) anyerror!void {
    try eff.writer.tell("helper");
}
