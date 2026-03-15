const program_bridge = @import("program_bridge");
const std = @import("std");
const unsupported_nested = @import("direct_style_bridge_unsupported_nested");

test "direct-style bridge rejects unsupported unchanged-body cases" {
    try std.testing.expectError(error.UnsupportedBridgeCase, program_bridge.lowerFixture(unsupported_nested));
}
