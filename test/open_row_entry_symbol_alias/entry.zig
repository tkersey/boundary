const helper_mod = @import("helper.zig");

/// Entry function that must stay selected even when a helper exports the same symbol name.
pub fn runBody(eff: anytype) anyerror!void {
    try helper_mod.runBody(eff);
    try eff.writer.tell("entry");
}
