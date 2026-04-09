const example = @import("example_open_row_state_writer");
const shift_compile = @import("shift_compile");
const shift_vm = @import("shift_vm");
const std = @import("std");

const custom_capabilities_a = [_]shift_vm.CapabilityV1{
    .{
        .capability_id = 11,
        .kind = .tool,
        .label = "generated/state@v1",
        .ops = &.{
            .{
                .capability_id = 11,
                .op_id = 4,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .i32,
                .plan_op_ordinal = 0,
            },
            .{
                .capability_id = 11,
                .op_id = 5,
                .global_op_name = "tool.call",
                .payload_codec = .i32,
                .result_codec = .unit,
                .plan_op_ordinal = 1,
            },
        },
    },
    .{
        .capability_id = 27,
        .kind = .tool,
        .label = "generated/writer@v1",
        .ops = &.{.{
            .capability_id = 27,
            .op_id = 9,
            .global_op_name = "tool.call",
            .payload_codec = .string,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    },
};

const custom_capabilities_b = [_]shift_vm.CapabilityV1{
    .{
        .capability_id = 41,
        .kind = .tool,
        .label = "generated/state@v1",
        .ops = &.{
            .{
                .capability_id = 41,
                .op_id = 0,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .i32,
                .plan_op_ordinal = 0,
            },
            .{
                .capability_id = 41,
                .op_id = 1,
                .global_op_name = "tool.call",
                .payload_codec = .i32,
                .result_codec = .unit,
                .plan_op_ordinal = 1,
            },
        },
    },
    .{
        .capability_id = 53,
        .kind = .tool,
        .label = "generated/writer@v1",
        .ops = &.{.{
            .capability_id = 53,
            .op_id = 12,
            .global_op_name = "tool.call",
            .payload_codec = .string,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    },
};

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

test "BundleEnvelopeV1 default compile path folds custom capability manifests into the build fingerprint" {
    const bytes_a = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .capabilities = &custom_capabilities_a,
        },
    );
    defer std.testing.allocator.free(bytes_a);

    const bytes_b = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .capabilities = &custom_capabilities_b,
        },
    );
    defer std.testing.allocator.free(bytes_b);

    var decoded_a = try shift_vm.artifact.decode(std.testing.allocator, bytes_a);
    defer decoded_a.deinit(std.testing.allocator);
    var decoded_b = try shift_vm.artifact.decode(std.testing.allocator, bytes_b);
    defer decoded_b.deinit(std.testing.allocator);

    const default_fingerprint = shift_vm.artifact.defaultBuildFingerprint();
    try std.testing.expect(!std.mem.eql(u8, &decoded_a.build_fingerprint_blake3_256, &default_fingerprint));
    try std.testing.expect(!std.mem.eql(u8, &decoded_a.build_fingerprint_blake3_256, &decoded_b.build_fingerprint_blake3_256));

    const envelope_bytes = try shift_vm.bundle.exportBundle(std.testing.allocator, bytes_a);
    defer std.testing.allocator.free(envelope_bytes);

    var imported = try shift_vm.bundle.importBundle(
        std.testing.allocator,
        envelope_bytes,
        decoded_a.build_fingerprint_blake3_256,
    );
    defer imported.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, bytes_a, imported.artifact_bytes);
    try std.testing.expectError(
        error.BuildFingerprintMismatch,
        shift_vm.bundle.importBundle(
            std.testing.allocator,
            envelope_bytes,
            decoded_b.build_fingerprint_blake3_256,
        ),
    );
}
