const helpers = @import("open_row_validation_snapshot_helper.zig");

/// Run one dedicated state-plus-writer workflow whose helper module exists only for snapshot-drift validation.
pub fn runBody(eff: anytype) ![]const u8 {
    try helpers.advanceState(eff);
    try eff.writer.tell("workflow=validation-snapshot");
    return "done";
}
