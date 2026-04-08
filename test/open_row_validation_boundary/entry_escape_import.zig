const helpers = @import("../../../examples/open_row_cross_file_helpers.zig");

/// Entry fixture that tries to escape the package root before re-entering it.
pub fn runBody(eff: anytype) anyerror!void {
    try helpers.advanceState(eff);
}
