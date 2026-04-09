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
