const example = @import("example_open_row_state_writer");
const shift_compile = @import("shift_compile");
const shift_vm = @import("shift_vm");
const std = @import("std");

test "BundleEnvelopeV1 round-trips ArtifactV1 bytes and rejects build mismatches" {
    const bytes = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "bundle-envelope-test",
            .capabilities = &.{},
        },
    );
    defer std.testing.allocator.free(bytes);

    const envelope_bytes = try shift_vm.bundle.exportBundle(std.testing.allocator, bytes);
    defer std.testing.allocator.free(envelope_bytes);

    const expected = shift_vm.artifact.buildFingerprintFromSeed("bundle-envelope-test");
    var imported = try shift_vm.bundle.importBundle(std.testing.allocator, envelope_bytes, expected);
    defer imported.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, bytes, imported.artifact_bytes);

    const wrong = shift_vm.artifact.buildFingerprintFromSeed("bundle-envelope-wrong");
    try std.testing.expectError(error.BuildFingerprintMismatch, shift_vm.bundle.importBundle(std.testing.allocator, envelope_bytes, wrong));
}

test "BundleEnvelopeV1 rejects truncated headers and invalid embedded artifacts" {
    const bytes = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "bundle-envelope-invalid",
            .capabilities = &.{},
        },
    );
    defer std.testing.allocator.free(bytes);

    const envelope_bytes = try shift_vm.bundle.exportBundle(std.testing.allocator, bytes);
    defer std.testing.allocator.free(envelope_bytes);

    const expected = shift_vm.artifact.buildFingerprintFromSeed("bundle-envelope-invalid");
    for ([_]usize{ 52, 60, 83 }) |len| {
        try std.testing.expectError(error.InvalidLength, shift_vm.bundle.importBundle(std.testing.allocator, envelope_bytes[0..len], expected));
    }

    var corrupted = try std.testing.allocator.dupe(u8, envelope_bytes);
    defer std.testing.allocator.free(corrupted);
    corrupted[84] ^= 0x1;
    var digest = std.mem.zeroes([32]u8);
    std.crypto.hash.Blake3.hash(corrupted[84..], &digest, .{});
    @memcpy(corrupted[44..76], &digest);

    try std.testing.expectError(error.InvalidArtifact, shift_vm.bundle.importBundle(std.testing.allocator, corrupted, expected));
}

test "BundleEnvelopeV1 rejects header fingerprints that disagree with the embedded artifact" {
    const bytes = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "bundle-envelope-original",
            .capabilities = &.{},
        },
    );
    defer std.testing.allocator.free(bytes);

    const envelope_bytes = try shift_vm.bundle.exportBundle(std.testing.allocator, bytes);
    defer std.testing.allocator.free(envelope_bytes);

    var mismatched = try std.testing.allocator.dupe(u8, envelope_bytes);
    defer std.testing.allocator.free(mismatched);
    const wrong_expected = shift_vm.artifact.buildFingerprintFromSeed("bundle-envelope-rewritten");
    @memcpy(mismatched[12..44], &wrong_expected);

    try std.testing.expectError(error.BuildFingerprintMismatch, shift_vm.bundle.importBundle(std.testing.allocator, mismatched, wrong_expected));
}

test "BundleEnvelopeV1 default compile path carries the current build fingerprint" {
    const bytes = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{},
    );
    defer std.testing.allocator.free(bytes);

    const envelope_bytes = try shift_vm.bundle.exportBundle(std.testing.allocator, bytes);
    defer std.testing.allocator.free(envelope_bytes);

    const expected = shift_vm.artifact.defaultBuildFingerprint();
    var imported = try shift_vm.bundle.importBundle(std.testing.allocator, envelope_bytes, expected);
    defer imported.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, bytes, imported.artifact_bytes);

    const wrong = shift_vm.artifact.buildFingerprintFromSeed("bundle-envelope-default-wrong");
    try std.testing.expectError(error.BuildFingerprintMismatch, shift_vm.bundle.importBundle(std.testing.allocator, envelope_bytes, wrong));
}
