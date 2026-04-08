const helpers = @import("./.compile_fail_escape_helper_link.zig");

/// Trigger one helper import boundary failure through a repo-local symlink helper.
pub fn runBody(eff: anytype) anyerror!void {
    try helpers.helper(eff);
}
