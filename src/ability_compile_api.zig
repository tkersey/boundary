const artifact = @import("artifact_api");
const lowering = @import("lowering_api");
const std = @import("std");

/// Compile-time options for ArtifactV1 emission and default capability derivation.
pub const CompileOptionsV1 = struct {
    /// Empty uses the current build-derived exact-build fingerprint.
    /// Non-empty folds the seed into that build identity instead of replacing it.
    build_fingerprint_seed: []const u8 = "",
    /// Non-empty replaces the build-derived identity for deterministic fixture emission.
    stable_build_fingerprint_seed: []const u8 = "",
    capabilities: []const artifact.CapabilityV1 = &.{},
};

fn artifactFingerprint(comptime options: CompileOptionsV1) [32]u8 {
    const default_fingerprint = artifact.defaultBuildFingerprint();
    if (options.stable_build_fingerprint_seed.len != 0) {
        return artifact.buildFingerprintFromSeed(options.stable_build_fingerprint_seed);
    }
    if (options.build_fingerprint_seed.len != 0) {
        return artifact.buildFingerprintWithSeed(default_fingerprint, options.build_fingerprint_seed);
    }
    return default_fingerprint;
}

fn CompilePlanType(
    comptime label: []const u8,
    comptime plan: lowering.ProgramPlan,
    comptime options: CompileOptionsV1,
) type {
    if (!std.mem.eql(u8, label, plan.label)) {
        @compileError(std.fmt.comptimePrint("ProgramPlan compile label mismatch: expected {s}, got {s}", .{ label, plan.label }));
    }
    if (plan.entry_index < plan.functions.len and plan.functions[plan.entry_index].parameter_count != 0) {
        @compileError(std.fmt.comptimePrint("ProgramPlan compile entry cannot require runtime parameters: {s}", .{plan.label}));
    }
    comptime plan.validate() catch |err| @compileError(std.fmt.comptimePrint("ProgramPlan compile failed: {s}", .{@errorName(err)}));
    return struct {
        /// Semantic plan hash carried through to ArtifactV1.
        pub const ir_hash = plan.ir_hash;
        /// Runtime-owned ProgramPlan compiled by this surface.
        pub const runtime_plan = plan;

        /// Execute the compiled ProgramPlan through native handlers.
        pub fn run(runtime: *lowering.Runtime, handlers: anytype) !lowering.ProgramPlanRunResult(runtime_plan) {
            return try lowering.runExecutablePlan(runtime, runtime_plan, handlers);
        }

        /// Encode the compiled runtime plan into canonical ArtifactV1 bytes.
        pub fn encodeArtifactV1(allocator: std.mem.Allocator) ![]u8 {
            var owned_capabilities: ?[]artifact.CapabilityV1 = null;
            defer if (owned_capabilities) |caps| {
                artifact.deepFreeCapabilities(allocator, caps);
            };
            const capabilities = if (options.capabilities.len == 0) blk: {
                owned_capabilities = try artifact.deriveToolCapabilitiesFromPlan(allocator, runtime_plan);
                break :blk owned_capabilities.?;
            } else options.capabilities;
            return artifact.encodeProgramPlan(allocator, runtime_plan, .{
                .build_fingerprint_blake3_256 = artifactFingerprint(options),
                .capabilities = capabilities,
            });
        }

        /// Decode ArtifactV1 bytes back into the public artifact surface.
        pub fn decodeArtifactV1(allocator: std.mem.Allocator, bytes: []const u8) !artifact.ArtifactV1 {
            return artifact.decode(allocator, bytes);
        }

        /// Render a readable disassembly for the compiled ArtifactV1 payload.
        pub fn disasmArtifactV1(allocator: std.mem.Allocator) ![]u8 {
            const bytes = try encodeArtifactV1(allocator);
            defer allocator.free(bytes);
            return artifact.disasmAlloc(allocator, bytes);
        }

        /// Backward-compatible ArtifactV1 encoder alias.
        pub const encode = encodeArtifactV1;
        /// Backward-compatible ArtifactV1 decoder alias.
        pub const decode = decodeArtifactV1;
        /// Backward-compatible disassembly alias.
        pub const disasmAlloc = disasmArtifactV1;
    };
}

/// Compile one runtime-owned ProgramPlan into a typed execution and ArtifactV1 surface.
pub const CompilePlan = CompilePlanType;

/// Public ProgramPlan-first compile entrypoint.
// zlinter-disable-next-line declaration_naming - public API intentionally mirrors lower-case compile verbs.
pub const compile = CompilePlanType;
