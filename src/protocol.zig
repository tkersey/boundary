// zlinter-disable declaration_naming no_inferred_error_unions no_panic require_doc_comment
const effect_ir = @import("effect_ir");
const loaded_execution = @import("loaded_execution");
const parity_scenarios = @import("parity_scenarios");
const plan = @import("internal_program_plan");
const protocol_version = @import("protocol_version.zig");
const std = @import("std");

pub const boundary_protocol_manifest_format_version: u32 = 1;
pub const boundary_protocol_manifest_fingerprint_version: u32 = 1;

pub const Protocol = struct {
    pub const Manifest = struct {
        pub const format_version: u32 = boundary_protocol_manifest_format_version;
        pub const fingerprint_version: u32 = boundary_protocol_manifest_fingerprint_version;
        pub const boundary_package_version = protocol_version.boundary_package_version;
        pub const minimum_zig_version = protocol_version.minimum_zig_version;
        pub const root_namespaces = &.{
            "effect",
            "Agent",
            "ir",
            "program",
            "Runtime",
            "Protocol",
            "boundary_protocol_manifest_format_version",
            "boundary_protocol_manifest_fingerprint_version",
        };
        pub const supported_build_gates = &.{
            "check",
            "check-boundary-protocol-manifest",
            "check-boundary-public-surface",
            "check-boundary-format-drift",
            "check-boundary-conformance-corpus",
            "check-boundary-adversarial-codecs",
            "check-boundary-v0-budgets",
            "check-boundary-agent-profile",
            "check-boundary-agent-modules",
            "check-boundary-agent-generated-loaded-parity",
            "check-boundary-agent-conformance-corpus",
            "update-boundary-agent-conformance-corpus",
            "check-boundary-loaded-v2-receipt-host",
            "check-boundary-loaded-session-receipt-host",
            "check-boundary-loaded-parity-receipt-host",
            "update-boundary-conformance-corpus",
            "emit-boundary-proof-receipts",
            "dist-boundary-protocol",
        };
        pub const required_feature_flags = &.{
            "portable-v2-loaded-execution-profile",
            "loaded-session-image-v2",
            "generated-loaded-parity-v1",
        };
        pub const optional_feature_flags = &.{
            "diagnostic-human-readable-manifest",
        };
        pub const generated_loaded_parity_scenarios = &.{
            "unit",
            "bool",
            "i32",
            "portable-word",
            "strings",
            "product",
            "sum",
            "helper-frame",
            "two-residual-requests",
            "helper-that-parks",
            "wrong-stale-duplicate-response-rejection",
        };
        pub const metadata_bytes: []const u8 = "";
        const portable_v2_limits = loaded_execution.LoadedExecutionProfile.portableV2().limits;
        const max_indexed_plan_count: u32 = std.math.maxInt(u16) + 1;

        pub const Limits = struct {
            max_module_image_bytes: u32 = 16 * 1024 * 1024,
            max_executable_plan_bytes: u32 = 4 * 1024 * 1024,
            max_loaded_value_bytes: u32 = loaded_execution.sessionOwnedValueImageByteLimit(portable_v2_limits),
            max_value_nesting: u16 = portable_v2_limits.maximum_value_nesting_depth,
            max_frame_depth: u16 = @intCast(@min(portable_v2_limits.maximum_call_depth, portable_v2_limits.maximum_frames)),
            max_locals: u16 = portable_v2_limits.maximum_locals_per_frame,
            max_instruction_fuel: u64 = portable_v2_limits.maximum_instructions_per_advancement,
            max_function_count: u32 = max_indexed_plan_count,
            max_block_count: u32 = max_indexed_plan_count,
            max_schema_count: u32 = max_indexed_plan_count,
        };

        pub const limits = Limits{};

        pub fn manifestFingerprint() u64 {
            var out: std.ArrayList(u8) = .empty;
            defer out.deinit(std.heap.page_allocator);
            encodeIdentity(std.heap.page_allocator, &out) catch @panic("boundary protocol manifest identity encoding failed");
            return fnv64(out.items);
        }

        pub fn publicSurfaceFingerprint() u64 {
            var out: std.ArrayList(u8) = .empty;
            defer out.deinit(std.heap.page_allocator);
            encodePublicSurfaceIdentity(std.heap.page_allocator, &out) catch @panic("boundary protocol public surface encoding failed");
            return fnv64(out.items);
        }

        pub fn encodeAlloc(allocator: std.mem.Allocator) ![]u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try appendBytes(&out, allocator, "BPM1");
            try appendU32(&out, allocator, format_version);
            try appendU32(&out, allocator, fingerprint_version);
            try appendU64(&out, allocator, manifestFingerprint());
            try encodeIdentity(allocator, &out);
            return out.toOwnedSlice(allocator);
        }

        fn encodeIdentity(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
            try appendU32(out, allocator, format_version);
            try appendU32(out, allocator, fingerprint_version);
            try appendU32(out, allocator, loaded_execution.executable_plan_image_format_version);
            try appendU32(out, allocator, loaded_execution.executable_plan_image_fingerprint_version);
            try appendU32(out, allocator, loaded_execution.loaded_execution_profile_format_version_v1);
            try appendU32(out, allocator, loaded_execution.loaded_execution_profile_format_version_v2);
            try appendU32(out, allocator, loaded_execution.loaded_execution_profile_fingerprint_version_v1);
            try appendU32(out, allocator, loaded_execution.loaded_execution_profile_fingerprint_version_v2);
            try appendU32(out, allocator, loaded_execution.loaded_session_image_format_version_v1);
            try appendU32(out, allocator, loaded_execution.loaded_session_image_format_version_v2);
            try appendU32(out, allocator, loaded_execution.loaded_session_image_fingerprint_version_v1);
            try appendU32(out, allocator, loaded_execution.loaded_session_image_fingerprint_version_v2);
            try appendU32(out, allocator, loaded_execution.loaded_value_image_format_version);
            try appendU32(out, allocator, loaded_execution.loaded_value_image_fingerprint_version);
            try appendEnumTable(allocator, out, "instruction", plan.InstructionKind);
            try appendEnumTable(allocator, out, "terminator", plan.TerminatorKind);
            try appendEnumTable(allocator, out, "value-codec", plan.ValueCodec);
            try appendEnumTable(allocator, out, "loaded-session-status", loaded_execution.LoadedSessionStatus);
            try appendEnumTable(allocator, out, "loaded-session-response-kind", loaded_execution.LoadedSessionResponseKind);
            try appendEnumTable(allocator, out, "execution-failure-kind", loaded_execution.ExecutionFailureKind);
            try appendEnumTable(allocator, out, "portable-arithmetic", loaded_execution.ArithmeticSemantics);
            try appendEnumTable(allocator, out, "portable-integer-width", loaded_execution.IntegerWidthSemantics);
            try appendEnumTable(allocator, out, "effect-ir-instruction", effect_ir.InstructionKind);
            try appendEnumTable(allocator, out, "effect-ir-terminator", effect_ir.TerminatorKind);
            try appendStringList(allocator, out, generated_loaded_parity_scenarios);
            try appendStringList(allocator, out, required_feature_flags);
            try appendStringList(allocator, out, optional_feature_flags);
            try appendU32(out, allocator, limits.max_module_image_bytes);
            try appendU32(out, allocator, limits.max_executable_plan_bytes);
            try appendU32(out, allocator, limits.max_loaded_value_bytes);
            try appendU16(out, allocator, limits.max_value_nesting);
            try appendU16(out, allocator, limits.max_frame_depth);
            try appendU16(out, allocator, limits.max_locals);
            try appendU64(out, allocator, limits.max_instruction_fuel);
            try appendU32(out, allocator, limits.max_function_count);
            try appendU32(out, allocator, limits.max_block_count);
            try appendU32(out, allocator, limits.max_schema_count);
            try appendU64(out, allocator, loaded_execution.LoadedExecutionProfile.portableV2().computeFingerprint());
            try appendU64(out, allocator, publicSurfaceFingerprint());
            try appendBytesWithLength(out, allocator, metadata_bytes);
            try appendEnumTable(allocator, out, "parity-scenario", parity_scenarios.ScenarioId);
        }

        fn encodePublicSurfaceIdentity(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
            try appendString(out, allocator, "boundary");
            try appendU32(out, allocator, format_version);
            try appendU32(out, allocator, fingerprint_version);
            try appendStringList(allocator, out, root_namespaces);
            try appendU32(out, allocator, loaded_execution.executable_plan_image_format_version);
            try appendU32(out, allocator, loaded_execution.executable_plan_image_fingerprint_version);
            try appendU32(out, allocator, loaded_execution.loaded_execution_profile_format_version_v1);
            try appendU32(out, allocator, loaded_execution.loaded_execution_profile_format_version_v2);
            try appendU32(out, allocator, loaded_execution.loaded_execution_profile_fingerprint_version_v1);
            try appendU32(out, allocator, loaded_execution.loaded_execution_profile_fingerprint_version_v2);
            try appendU32(out, allocator, loaded_execution.loaded_session_image_format_version_v1);
            try appendU32(out, allocator, loaded_execution.loaded_session_image_format_version_v2);
            try appendU32(out, allocator, loaded_execution.loaded_session_image_fingerprint_version_v1);
            try appendU32(out, allocator, loaded_execution.loaded_session_image_fingerprint_version_v2);
            try appendU32(out, allocator, loaded_execution.loaded_value_image_format_version);
            try appendU32(out, allocator, loaded_execution.loaded_value_image_fingerprint_version);
            try appendEnumTable(allocator, out, "instruction", plan.InstructionKind);
            try appendEnumTable(allocator, out, "terminator", plan.TerminatorKind);
            try appendEnumTable(allocator, out, "value-codec", plan.ValueCodec);
            try appendEnumTable(allocator, out, "loaded-session-status", loaded_execution.LoadedSessionStatus);
            try appendEnumTable(allocator, out, "loaded-session-response-kind", loaded_execution.LoadedSessionResponseKind);
            try appendEnumTable(allocator, out, "execution-failure-kind", loaded_execution.ExecutionFailureKind);
            try appendEnumTable(allocator, out, "effect-ir-instruction", effect_ir.InstructionKind);
            try appendEnumTable(allocator, out, "effect-ir-terminator", effect_ir.TerminatorKind);
            try appendStringList(allocator, out, supported_build_gates);
        }
    };
};

fn appendEnumTable(allocator: std.mem.Allocator, out: *std.ArrayList(u8), domain: []const u8, comptime T: type) !void {
    try appendString(out, allocator, domain);
    const fields = @typeInfo(T).@"enum".fields;
    try appendU32(out, allocator, @intCast(fields.len));
    inline for (fields) |field| {
        try appendString(out, allocator, field.name);
        try appendU64(out, allocator, @intCast(field.value));
    }
}

fn appendStringList(allocator: std.mem.Allocator, out: *std.ArrayList(u8), values: []const []const u8) !void {
    try appendU32(out, allocator, @intCast(values.len));
    for (values) |value| try appendString(out, allocator, value);
}

fn appendString(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try appendBytesWithLength(out, allocator, value);
}

fn appendBytesWithLength(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try appendU32(out, allocator, @intCast(value.len));
    try appendBytes(out, allocator, value);
}

fn appendBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try out.appendSlice(allocator, value);
}

fn appendU16(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, value, .little);
    try appendBytes(out, allocator, &buf);
}

fn appendU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try appendBytes(out, allocator, &buf);
}

fn appendU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    try appendBytes(out, allocator, &buf);
}

fn fnv64(bytes: []const u8) u64 {
    var hash: u64 = 14695981039346656037;
    for (bytes) |byte| {
        hash ^= byte;
        hash *%= 1099511628211;
    }
    return hash;
}

test "boundary protocol manifest has deterministic canonical identity" {
    const allocator = std.testing.allocator;
    const first = try Protocol.Manifest.encodeAlloc(allocator);
    defer allocator.free(first);
    const second = try Protocol.Manifest.encodeAlloc(allocator);
    defer allocator.free(second);

    try std.testing.expectEqualSlices(u8, first, second);
    try std.testing.expect(first.len > 128);
    try std.testing.expectEqual(@as(u32, 1), boundary_protocol_manifest_format_version);
    try std.testing.expectEqual(@as(u32, 1), boundary_protocol_manifest_fingerprint_version);
    try std.testing.expect(Protocol.Manifest.manifestFingerprint() != 0);
    try std.testing.expect(Protocol.Manifest.publicSurfaceFingerprint() != 0);
    try std.testing.expectEqual(@as(u32, 2), loaded_execution.boundary_loaded_execution_profile_version);
}

test "boundary protocol fingerprints exclude package release metadata" {
    const allocator = std.testing.allocator;

    var manifest_identity: std.ArrayList(u8) = .empty;
    defer manifest_identity.deinit(allocator);
    try Protocol.Manifest.encodeIdentity(allocator, &manifest_identity);

    var public_surface_identity: std.ArrayList(u8) = .empty;
    defer public_surface_identity.deinit(allocator);
    try Protocol.Manifest.encodePublicSurfaceIdentity(allocator, &public_surface_identity);

    try std.testing.expect(std.mem.find(u8, manifest_identity.items, Protocol.Manifest.boundary_package_version) == null);
    try std.testing.expect(std.mem.find(u8, public_surface_identity.items, Protocol.Manifest.boundary_package_version) == null);
}
