const artifact = @import("shift_shared").artifact;
const compile_shared = @import("shift_shared");
const lowering = compile_shared.lowering;
const std = @import("std");

pub const CompileOptionsV1 = struct {
    build_fingerprint_seed: []const u8 = "shift-compile-v1",
    capabilities: []const artifact.CapabilityV1 = &.{},
};

pub fn compileSource(
    comptime source_path: []const u8,
    comptime spec: lowering.LowerSpec,
    comptime options: CompileOptionsV1,
) type {
    const Lowered = lowering.lowerAt(source_path, spec);
    return struct {
        pub const ir_hash = Lowered.ir_hash;
        pub const runtime_plan = Lowered.runtime_plan;

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
            return artifact.encodeProgramPlan(allocator, runtime_plan, .{
                .build_fingerprint_blake3_256 = artifact.buildFingerprintFromSeed(options.build_fingerprint_seed),
                .capabilities = capabilities,
            });
        }

        pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !artifact.ArtifactV1 {
            return artifact.decode(allocator, bytes);
        }

        pub fn disasmAlloc(allocator: std.mem.Allocator) ![]u8 {
            const bytes = try encode(allocator);
            defer allocator.free(bytes);
            return artifact.disasmAlloc(allocator, bytes);
        }
    };
}

pub fn compileAndEncode(
    allocator: std.mem.Allocator,
    comptime source_path: []const u8,
    comptime spec: lowering.LowerSpec,
    comptime options: CompileOptionsV1,
) ![]u8 {
    return compileSource(source_path, spec, options).encode(allocator);
}
