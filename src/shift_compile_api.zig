const artifact = @import("shift_shared").artifact;
const compile_shared = @import("shift_shared");
const lowering = compile_shared.lowering;
const std = @import("std");

/// Compile-time options for ArtifactV1 emission and default capability derivation.
pub const CompileOptionsV1 = struct {
    /// Empty uses the current build-derived exact-build fingerprint.
    build_fingerprint_seed: []const u8 = "",
    capabilities: []const artifact.CapabilityV1 = &.{},
};

fn CompileSourceType(
    comptime source_path: []const u8,
    comptime spec: lowering.LowerSpec,
    comptime options: CompileOptionsV1,
) type {
    const Lowered = lowering.lowerAt(source_path, spec);
    return struct {
        /// Semantic IR hash carried through to ArtifactV1.
        pub const ir_hash = Lowered.ir_hash;
        /// Runtime-owned plan produced by the compile path.
        pub const runtime_plan = Lowered.runtime_plan;

        /// Encode the compiled runtime plan into canonical ArtifactV1 bytes.
        pub fn encode(allocator: std.mem.Allocator) ![]u8 {
            var owned_capabilities: ?[]artifact.CapabilityV1 = null;
            defer if (owned_capabilities) |caps| {
                const mutable_caps = caps;
                artifact.deepFreeCapabilities(allocator, mutable_caps);
            };
            const capabilities = if (options.capabilities.len == 0) blk: {
                owned_capabilities = try artifact.deriveToolCapabilitiesFromPlan(allocator, runtime_plan);
                break :blk owned_capabilities.?;
            } else options.capabilities;

            const base_fingerprint = if (options.build_fingerprint_seed.len != 0)
                artifact.buildFingerprintFromSeed(options.build_fingerprint_seed)
            else
                artifact.defaultBuildFingerprint();
            const build_fingerprint = try artifact.buildFingerprintForCapabilities(
                allocator,
                base_fingerprint,
                capabilities,
            );
            return artifact.encodeProgramPlan(allocator, runtime_plan, .{
                .build_fingerprint_blake3_256 = build_fingerprint,
                .capabilities = capabilities,
            });
        }

        /// Decode ArtifactV1 bytes back into the public VM artifact surface.
        pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !artifact.ArtifactV1 {
            return artifact.decode(allocator, bytes);
        }

        /// Render a readable disassembly for the compiled ArtifactV1 payload.
        pub fn disasmAlloc(allocator: std.mem.Allocator) ![]u8 {
            const bytes = try encode(allocator);
            defer allocator.free(bytes);
            return artifact.disasmAlloc(allocator, bytes);
        }
    };
}

/// Compile one repo-owned source path into a typed ArtifactV1 emission surface.
pub const CompileSource = CompileSourceType;

/// Compile one repo-owned source path and emit ArtifactV1 bytes immediately.
pub fn compileAndEncode(
    allocator: std.mem.Allocator,
    comptime source_path: []const u8,
    comptime spec: lowering.LowerSpec,
    comptime options: CompileOptionsV1,
) ![]u8 {
    return CompileSource(source_path, spec, options).encode(allocator);
}
