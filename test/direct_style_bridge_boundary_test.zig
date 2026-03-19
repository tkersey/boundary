const bridge_manifest = @import("direct_style_bridge_manifest");
const early_exit = @import("direct_style_bridge_early_exit");
const private_lowered_runtime = @import("private_lowered_runtime");
const program_bridge = @import("program_bridge");
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

test "bridge fixtures still execute when callers chdir outside the repo root" {
    const original_cwd = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(original_cwd);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(original_cwd) catch unreachable;

    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const execution = try private_lowered_runtime.runBridgeFixture(early_exit, &writer);
    try std.testing.expectEqualStrings("bridge.early_exit", execution.label);
    try std.testing.expectEqualStrings("early_exit", execution.scenario.case_id);
}

test "bridge case ids still execute through the lowered runtime seam" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const execution = try private_lowered_runtime.runCaseId(&writer, "early_exit");
    try std.testing.expectEqualStrings("bridge.early_exit", execution.label);
    try std.testing.expectEqualStrings("early_exit", execution.scenario.case_id);
}

test "bridge case-id admission rejects drifted canonical sources" {
    const drifted =
        \\const shift = @import("shift");
        \\
        \\pub const bridge_case_id = "early_exit";
        \\
        \\pub fn run(writer: anytype) !void {
        \\    _ = shift;
        \\    try writer.writeAll("status=late\\n");
        \\}
    ;

    var lowered = try program_bridge.inspectCaseIdSourceText(std.testing.allocator, "early_exit", drifted);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.status == .rejected);
    try std.testing.expectEqualStrings("canonical_source_drift", lowered.diagnostics[0].code);
}
