/// Emit the `a` witness so imported helper resolution can distinguish this module.
pub fn helper(eff: anytype) anyerror!void {
    try eff.writer.tell("a");
}
