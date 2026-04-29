const fixture_options = @import("agent_vm_conformance_fixture_options");
const report = @import("agent_vm_artifact_report");
const std = @import("std");

fn loadFixtureBytes(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(
        std.Io.Threaded.global_single_threaded.io(),
        path,
        allocator,
        .limited(report.max_artifact_bytes + 1),
    );
}

test "agent-vm-artifact-report parses artifact flag" {
    const parsed = report.parseArgs(&.{ "agent-vm-artifact-report", "--artifact", "artifact.bin" });
    try std.testing.expectEqualStrings("artifact.bin", parsed.artifact_path);
    try std.testing.expect(report.parseArgs(&.{ "agent-vm-artifact-report", "--help" }) == .help);
    try std.testing.expect(report.parseArgs(&.{"agent-vm-artifact-report"}) == .invalid);
}

test "agent-vm-artifact-report classifies compatible, unsupported, invalid, and incompatible artifacts" {
    const allocator = std.testing.allocator;
    const compatible_bytes = try loadFixtureBytes(allocator, fixture_options.no_host_artifact_path);
    defer allocator.free(compatible_bytes);
    const compatible = try report.fixedProfileVerdict(allocator, compatible_bytes);
    try std.testing.expectEqual(report.VerdictStatus.compatible, compatible.status);
    try std.testing.expectEqualStrings("ok", compatible.code);

    const host_call_bytes = try loadFixtureBytes(allocator, fixture_options.host_call_artifact_path);
    defer allocator.free(host_call_bytes);
    const unsupported = try report.fixedProfileVerdict(allocator, host_call_bytes);
    try std.testing.expectEqual(report.VerdictStatus.unsupported, unsupported.status);
    try std.testing.expectEqualStrings("host_call", unsupported.code);

    var invalid_bytes = std.mem.zeroes([128]u8);
    const invalid = try report.fixedProfileVerdict(allocator, &invalid_bytes);
    try std.testing.expectEqual(report.VerdictStatus.invalid, invalid.status);
    try std.testing.expectEqualStrings("invalid_artifact", invalid.code);

    const oversized_bytes = try loadFixtureBytes(allocator, fixture_options.oversized_return_artifact_path);
    defer allocator.free(oversized_bytes);
    const incompatible = try report.fixedProfileVerdict(allocator, oversized_bytes);
    try std.testing.expectEqual(report.VerdictStatus.incompatible, incompatible.status);
    try std.testing.expectEqualStrings("resource_exhausted", incompatible.code);
}
