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
    try std.testing.expectEqualStrings("artifact.bin", parsed.artifact.path);
    try std.testing.expectEqual(report.OutputFormat.text, parsed.artifact.format);
    const dashed_path = report.parseArgs(&.{ "agent-vm-artifact-report", "--artifact", "--fixture.artifact" });
    try std.testing.expectEqualStrings("--fixture.artifact", dashed_path.artifact.path);
    const json_parsed = report.parseArgs(&.{ "agent-vm-artifact-report", "--json", "--artifact", "artifact.bin" });
    try std.testing.expectEqualStrings("artifact.bin", json_parsed.artifact.path);
    try std.testing.expectEqual(report.OutputFormat.json, json_parsed.artifact.format);
    try std.testing.expect(!json_parsed.artifact.report_only);
    const report_only_parsed = report.parseArgs(&.{ "agent-vm-artifact-report", "--report-only", "--format", "json", "--artifact", "artifact.bin" });
    try std.testing.expectEqualStrings("artifact.bin", report_only_parsed.artifact.path);
    try std.testing.expectEqual(report.OutputFormat.json, report_only_parsed.artifact.format);
    try std.testing.expect(report_only_parsed.artifact.report_only);
    const format_json_parsed = report.parseArgs(&.{ "agent-vm-artifact-report", "--format", "json", "--artifact", "artifact.bin" });
    try std.testing.expectEqualStrings("artifact.bin", format_json_parsed.artifact.path);
    try std.testing.expectEqual(report.OutputFormat.json, format_json_parsed.artifact.format);
    try std.testing.expectEqualStrings(
        "choose either --json or --format <text|json>, not both",
        report.parseArgs(&.{ "agent-vm-artifact-report", "--json", "--format", "text", "--artifact", "artifact.bin" }).invalid,
    );
    try std.testing.expectEqualStrings(
        "choose either --json or --format <text|json>, not both",
        report.parseArgs(&.{ "agent-vm-artifact-report", "--format", "text", "--json", "--artifact", "artifact.bin" }).invalid,
    );
    try std.testing.expectEqualStrings(
        "duplicate --format flag",
        report.parseArgs(&.{ "agent-vm-artifact-report", "--format", "json", "--format", "text", "--artifact", "artifact.bin" }).invalid,
    );
    try std.testing.expectEqualStrings(
        "duplicate --json flag",
        report.parseArgs(&.{ "agent-vm-artifact-report", "--json", "--json", "--artifact", "artifact.bin" }).invalid,
    );
    try std.testing.expectEqualStrings(
        "duplicate --report-only flag",
        report.parseArgs(&.{ "agent-vm-artifact-report", "--report-only", "--report-only", "--artifact", "artifact.bin" }).invalid,
    );
    try std.testing.expectEqualStrings(
        "--json",
        report.parseArgs(&.{ "agent-vm-artifact-report", "--artifact", "--json" }).artifact.path,
    );
    try std.testing.expectEqualStrings(
        "--fixture.artifact",
        report.parseArgs(&.{ "agent-vm-artifact-report", "--artifact", "--fixture.artifact" }).artifact.path,
    );
    try std.testing.expect(report.parseArgs(&.{ "agent-vm-artifact-report", "--help" }) == .help);
    try std.testing.expect(report.parseArgs(&.{ "agent-vm-artifact-report", "--help", "--artifact", "artifact.bin" }) == .help);
    try std.testing.expect(report.parseArgs(&.{ "agent-vm-artifact-report", "--version" }) == .version);
    try std.testing.expect(report.parseArgs(&.{ "agent-vm-artifact-report", "--json", "--version" }) == .version);
    try std.testing.expectEqualStrings(
        "missing required --artifact <path>",
        report.parseArgs(&.{"agent-vm-artifact-report"}).invalid,
    );
    try std.testing.expectEqualStrings(
        "extra",
        report.parseArgs(&.{ "agent-vm-artifact-report", "--artifact", "artifact.bin", "extra" }).unexpected_arg,
    );
    try std.testing.expectEqualStrings(
        "--bad",
        report.parseArgs(&.{ "agent-vm-artifact-report", "--bad" }).unknown_arg,
    );
    try std.testing.expectEqual(report.OutputFormat.json, report.parseErrorOutputFormat(&.{ "agent-vm-artifact-report", "--json", "--bad" }));
    try std.testing.expectEqual(report.OutputFormat.json, report.parseErrorOutputFormat(&.{ "agent-vm-artifact-report", "--format", "json", "--bad" }));
    try std.testing.expectEqual(report.OutputFormat.json, report.parseErrorOutputFormat(&.{ "agent-vm-artifact-report", "--format", "--json", "--bad" }));
    try std.testing.expectEqual(report.OutputFormat.text, report.parseErrorOutputFormat(&.{ "agent-vm-artifact-report", "--format", "text", "--bad" }));
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

    const output_snapshot_bytes = try loadFixtureBytes(allocator, fixture_options.output_snapshot_artifact_path);
    defer allocator.free(output_snapshot_bytes);
    const output_snapshot = try report.fixedProfileVerdict(allocator, output_snapshot_bytes);
    try std.testing.expectEqual(report.VerdictStatus.unsupported, output_snapshot.status);
    try std.testing.expectEqualStrings("output_snapshot", output_snapshot.code);
    try std.testing.expectEqualStrings(
        "artifact declares output snapshots, which this fixed no-host report cannot inspect; rebuild without declared outputs or use a host-aware artifact inspection path",
        output_snapshot.detail,
    );

    var invalid_bytes = std.mem.zeroes([128]u8);
    const invalid = try report.fixedProfileVerdict(allocator, &invalid_bytes);
    try std.testing.expectEqual(report.VerdictStatus.invalid, invalid.status);
    try std.testing.expectEqualStrings("invalid_artifact", invalid.code);
    try std.testing.expectEqualStrings(
        "invalid artifact (BadMagic): file is not an Ability ArtifactV1 payload or is corrupted; pass an artifact generated by the matching ability toolchain",
        invalid.detail,
    );

    const oversized_bytes = try loadFixtureBytes(allocator, fixture_options.oversized_return_artifact_path);
    defer allocator.free(oversized_bytes);
    const incompatible = try report.fixedProfileVerdict(allocator, oversized_bytes);
    try std.testing.expectEqual(report.VerdictStatus.incompatible, incompatible.status);
    try std.testing.expectEqualStrings("resource_exhausted", incompatible.code);
    try std.testing.expectEqualStrings("artifact completed value payload budget exceeded", incompatible.detail);
}

test "agent-vm-artifact-report classifies in-memory artifacts over artifact-size profile cap" {
    const allocator = std.testing.allocator;
    const oversized_bytes = try allocator.alloc(u8, report.max_artifact_bytes + 1);
    defer allocator.free(oversized_bytes);
    @memset(oversized_bytes, 0);

    const verdict = try report.fixedProfileVerdict(allocator, oversized_bytes);
    try std.testing.expectEqual(report.VerdictStatus.incompatible, verdict.status);
    try std.testing.expectEqualStrings("resource_exhausted", verdict.code);
    try std.testing.expectEqualStrings(
        "artifact size exceeds fixed conformance profile limit max_artifact_bytes=16777216",
        verdict.detail,
    );
}

test "agent-vm-artifact-report classifies files over artifact-size profile cap" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const oversized_bytes = try allocator.alloc(u8, report.max_artifact_bytes + 1);
    defer allocator.free(oversized_bytes);
    @memset(oversized_bytes, 0);

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "oversized.artifact",
        .data = oversized_bytes,
    });
    const artifact_path = try tmp.dir.realPathFileAlloc(std.testing.io, "oversized.artifact", allocator);
    defer allocator.free(artifact_path);

    const read_result = try report.readArtifactForReport(std.testing.io, allocator, artifact_path);
    switch (read_result) {
        .bytes => |bytes| {
            allocator.free(bytes);
            return error.TestExpectedOversizedArtifactVerdict;
        },
        .verdict => |verdict| {
            try std.testing.expectEqual(report.VerdictStatus.incompatible, verdict.status);
            try std.testing.expectEqualStrings("resource_exhausted", verdict.code);
            try std.testing.expectEqualStrings(
                "artifact size exceeds fixed conformance profile limit max_artifact_bytes=16777216",
                verdict.detail,
            );
        },
    }
}

test "agent-vm-artifact-report maps read failures to stable JSON verdict fields" {
    const verdict = report.artifactReadFailureVerdict(error.FileNotFound);
    try std.testing.expectEqual(report.VerdictStatus.invalid, verdict.status);
    try std.testing.expectEqualStrings("artifact_read_failed", verdict.code);
    try std.testing.expectEqualStrings(
        "artifact file could not be read (FileNotFound): pass an existing ArtifactV1 file with --artifact <path>",
        verdict.detail,
    );
}
