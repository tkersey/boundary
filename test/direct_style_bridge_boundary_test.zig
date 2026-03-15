const bridge_manifest = @import("direct_style_bridge_manifest");
const std = @import("std");

test "direct-style bridge manifest has no blocked core cases" {
    for (bridge_manifest.cases) |case| {
        try std.testing.expect(case.status == .supported);
    }
}
