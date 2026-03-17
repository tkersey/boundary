const bridge_manifest = @import("direct_style_bridge_manifest");
const private_lowered_runtime = @import("private_lowered_runtime");
const std = @import("std");
const witness_admission = @import("witness_admission_registry");

test "direct-style bridge manifest stays aligned with witness admission truth" {
    for (witness_admission.entries) |entry| {
        const case = bridge_manifest.find(entry.witness_id).?;
        const expected_supported = entry.bridge_status == .supported;
        try std.testing.expectEqual(expected_supported, case.status == .supported);
        if (!expected_supported) {
            try std.testing.expect(case.blocked_reason != null);
        }
    }
}

test "blocked bridge witness cases fail closed through the lowered seam" {
    for (bridge_manifest.cases) |case| {
        if (case.status != .blocked) continue;
        try std.testing.expect(case.blocked_reason != null);
        var buffer: [1]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        try std.testing.expectError(error.UnsupportedBridgeCase, private_lowered_runtime.runCaseId(&writer, case.case_id));
    }
}
