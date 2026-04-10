const example = @import("example_open_row_state_writer");
const shift_compile = @import("shift_compile");
const shift_vm = @import("shift_vm");
const std = @import("std");

const custom_capabilities_alpha = [_]shift_vm.CapabilityV1{
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
    .{
        .capability_id = 41,
        .kind = .tool,
        .label = "generated/state@v1",
        .ops = &.{
            .{
                .capability_id = 41,
                .op_id = 14,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .i32,
                .plan_op_ordinal = 0,
            },
            .{
                .capability_id = 41,
                .op_id = 15,
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
            .op_id = 19,
            .global_op_name = "tool.call",
            .payload_codec = .string,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    },
    .{
        .capability_id = 65,
        .kind = .tool,
        .label = "generated/writer@v1",
        .ops = &.{.{
            .capability_id = 65,
            .op_id = 24,
            .global_op_name = "tool.call",
            .payload_codec = .string,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    },
};

const custom_capabilities_bravo = [_]shift_vm.CapabilityV1{
    .{
        .capability_id = 12,
        .kind = .tool,
        .label = "generated/state@v1",
        .ops = &.{
            .{
                .capability_id = 12,
                .op_id = 0,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .i32,
                .plan_op_ordinal = 0,
            },
            .{
                .capability_id = 12,
                .op_id = 1,
                .global_op_name = "tool.call",
                .payload_codec = .i32,
                .result_codec = .unit,
                .plan_op_ordinal = 1,
            },
        },
    },
    .{
        .capability_id = 28,
        .kind = .tool,
        .label = "generated/writer@v1",
        .ops = &.{.{
            .capability_id = 28,
            .op_id = 6,
            .global_op_name = "tool.call",
            .payload_codec = .string,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    },
    .{
        .capability_id = 42,
        .kind = .tool,
        .label = "generated/state@v1",
        .ops = &.{
            .{
                .capability_id = 42,
                .op_id = 10,
                .global_op_name = "tool.call",
                .payload_codec = .unit,
                .result_codec = .i32,
                .plan_op_ordinal = 0,
            },
            .{
                .capability_id = 42,
                .op_id = 11,
                .global_op_name = "tool.call",
                .payload_codec = .i32,
                .result_codec = .unit,
                .plan_op_ordinal = 1,
            },
        },
    },
    .{
        .capability_id = 54,
        .kind = .tool,
        .label = "generated/writer@v1",
        .ops = &.{.{
            .capability_id = 54,
            .op_id = 16,
            .global_op_name = "tool.call",
            .payload_codec = .string,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    },
    .{
        .capability_id = 66,
        .kind = .tool,
        .label = "generated/writer@v1",
        .ops = &.{.{
            .capability_id = 66,
            .op_id = 21,
            .global_op_name = "tool.call",
            .payload_codec = .string,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    },
};

test "CompileSource encodes repo-owned authored programs into ArtifactV1 bytes" {
    const Compiler = shift_compile.CompileSource(
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "artifact-api-test",
            .capabilities = &.{},
        },
    );

    const bytes = try Compiler.encode(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    var decoded = try shift_vm.artifact.decode(std.testing.allocator, bytes);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(Compiler.ir_hash, decoded.semantic_ir_hash64);
    try std.testing.expectEqual(@as(usize, Compiler.runtime_plan.functions.len), decoded.functions.len);
    try std.testing.expectEqual(@as(usize, Compiler.runtime_plan.instructions.len), decoded.instructions.len);
    try std.testing.expectEqual(@as(usize, Compiler.runtime_plan.requirements.len), decoded.requirement_capability_ids.len);
}

test "compileAndEncode produces readable disasm" {
    const bytes = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "artifact-disasm-test",
            .capabilities = &.{},
        },
    );
    defer std.testing.allocator.free(bytes);

    const disasm = try shift_vm.artifact.disasmAlloc(std.testing.allocator, bytes);
    defer std.testing.allocator.free(disasm);

    try std.testing.expect(std.mem.indexOf(u8, disasm, "ArtifactV1") != null);
    try std.testing.expect(std.mem.indexOf(u8, disasm, "functions=") != null);
}

test "CompileSource default path hashes derived capability manifests into the build fingerprint" {
    const Source = shift_compile.CompileSource(
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{},
    );
    const derived_capabilities = try shift_vm.artifact.deriveToolCapabilitiesFromPlan(
        std.testing.allocator,
        Source.runtime_plan,
    );
    defer shift_vm.artifact.deepFreeCapabilities(std.testing.allocator, derived_capabilities);

    const expected_fingerprint = try shift_vm.artifact.buildFingerprintForCapabilities(
        std.testing.allocator,
        shift_vm.artifact.defaultBuildFingerprint(),
        derived_capabilities,
    );
    const bytes = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{},
    );
    defer std.testing.allocator.free(bytes);

    var decoded = try shift_vm.artifact.decode(std.testing.allocator, bytes);
    defer decoded.deinit(std.testing.allocator);

    const explicit_bytes = try shift_vm.artifact.encodeProgramPlan(
        std.testing.allocator,
        Source.runtime_plan,
        .{
            .build_fingerprint_blake3_256 = expected_fingerprint,
            .capabilities = derived_capabilities,
        },
    );
    defer std.testing.allocator.free(explicit_bytes);

    try std.testing.expectEqual(expected_fingerprint, decoded.build_fingerprint_blake3_256);
    try std.testing.expect(!std.mem.eql(u8, &decoded.build_fingerprint_blake3_256, &shift_vm.artifact.defaultBuildFingerprint()));
    try std.testing.expectEqualSlices(u8, explicit_bytes, bytes);
}

test "CompileSource folds custom capability manifests into seeded build fingerprints" {
    const seeded_default_fingerprint = shift_vm.artifact.buildFingerprintWithSeed(
        shift_vm.artifact.defaultBuildFingerprint(),
        "artifact-api-seeded-capabilities",
    );
    const bytes_alpha = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "artifact-api-seeded-capabilities",
            .capabilities = &custom_capabilities_alpha,
        },
    );
    defer std.testing.allocator.free(bytes_alpha);

    const bytes_bravo = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "artifact-api-seeded-capabilities",
            .capabilities = &custom_capabilities_bravo,
        },
    );
    defer std.testing.allocator.free(bytes_bravo);

    var decoded_alpha = try shift_vm.artifact.decode(std.testing.allocator, bytes_alpha);
    defer decoded_alpha.deinit(std.testing.allocator);
    var decoded_bravo = try shift_vm.artifact.decode(std.testing.allocator, bytes_bravo);
    defer decoded_bravo.deinit(std.testing.allocator);

    const seed_fingerprint = shift_vm.artifact.buildFingerprintFromSeed("artifact-api-seeded-capabilities");
    const expected_alpha = try shift_vm.artifact.buildFingerprintForCapabilities(
        std.testing.allocator,
        seeded_default_fingerprint,
        &custom_capabilities_alpha,
    );
    const expected_bravo = try shift_vm.artifact.buildFingerprintForCapabilities(
        std.testing.allocator,
        seeded_default_fingerprint,
        &custom_capabilities_bravo,
    );
    const seed_only_alpha = try shift_vm.artifact.buildFingerprintForCapabilities(
        std.testing.allocator,
        seed_fingerprint,
        &custom_capabilities_alpha,
    );

    try std.testing.expectEqual(expected_alpha, decoded_alpha.build_fingerprint_blake3_256);
    try std.testing.expectEqual(expected_bravo, decoded_bravo.build_fingerprint_blake3_256);
    try std.testing.expect(!std.mem.eql(u8, &decoded_alpha.build_fingerprint_blake3_256, &seed_fingerprint));
    try std.testing.expect(!std.mem.eql(u8, &decoded_alpha.build_fingerprint_blake3_256, &seed_only_alpha));
    try std.testing.expect(!std.mem.eql(u8, &decoded_alpha.build_fingerprint_blake3_256, &decoded_bravo.build_fingerprint_blake3_256));
}
