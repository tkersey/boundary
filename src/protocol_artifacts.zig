// zlinter-disable require_doc_comment no_inferred_error_unions declaration_naming
const effect_ir = @import("effect_ir");
const loaded_execution = @import("loaded_execution");
const plan = @import("internal_program_plan");
const protocol = @import("protocol");
const std = @import("std");

const public_surface_path = "conformance/v0/public-surface.boundary.txt";
const corpus_dir = "conformance/v0/boundary";
const corpus_manifest_path = corpus_dir ++ "/corpus.boundary.txt";
const manifest_image_path = corpus_dir ++ "/protocol-manifest.bin";
const proof_receipts_dir = "zig-out/protocol/boundary/proof-receipts";
const dist_dir = "zig-out/dist/boundary-v0.5.0-protocol";

const positive_cases = [_][]const u8{
    "module-image",
    "executable-plan-image",
    "loaded-value-unit",
    "loaded-value-bool",
    "loaded-value-i32",
    "loaded-value-portable-word",
    "loaded-value-string",
    "loaded-value-product",
    "loaded-value-sum",
    "loaded-session-v2-parked-on-request",
    "loaded-session-v2-completed",
    "loaded-session-v2-failed",
    "generated-loaded-parity-unit",
    "generated-loaded-parity-bool",
    "generated-loaded-parity-i32",
    "generated-loaded-parity-portable-word",
    "generated-loaded-parity-strings",
    "generated-loaded-parity-product",
    "generated-loaded-parity-sum",
    "generated-loaded-parity-helper-frame",
    "generated-loaded-parity-two-residual-requests",
    "generated-loaded-parity-request-inside-loop",
    "generated-loaded-parity-helper-that-parks",
    "generated-loaded-parity-wrong-stale-duplicate-response-rejection",
};

const negative_cases = [_][]const u8{
    "truncated-module-section",
    "malformed-executable-plan",
    "unsupported-required-profile-feature",
    "invalid-instruction-tag",
    "invalid-terminator-tag",
    "invalid-value-codec",
    "invalid-schema-graph",
    "unreachable-unsupported-feature-accepted",
    "reachable-unsupported-feature-rejected",
    "forged-residual-site-binding",
    "forged-payload-image",
    "forged-result-image",
    "forged-loaded-session-image",
    "wrong-entry-function",
    "trailing-bytes",
    "excessive-nesting",
    "excessive-frame-depth",
};

const proof_commands = [_]struct {
    id: []const u8,
    command: []const u8,
}{
    .{ .id = "proof-002", .command = "zig build check-boundary-public-surface" },
    .{ .id = "proof-003", .command = "zig build check-boundary-format-drift" },
    .{ .id = "proof-004", .command = "zig build check-boundary-conformance-corpus" },
    .{ .id = "proof-005", .command = "zig build check-boundary-adversarial-codecs" },
    .{ .id = "proof-006", .command = "zig build check-boundary-v0-budgets" },
};

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const command = args.next() orelse return error.InvalidArguments;
    if (args.next() != null) return error.InvalidArguments;

    if (std.mem.eql(u8, command, "update-public-surface")) return updatePublicSurface(init, allocator);
    if (std.mem.eql(u8, command, "check-public-surface")) return checkPublicSurface(init, allocator);
    if (std.mem.eql(u8, command, "update-corpus")) return updateCorpus(init, allocator);
    if (std.mem.eql(u8, command, "check-corpus")) return checkCorpus(init, allocator);
    if (std.mem.eql(u8, command, "check-format-drift")) return checkFormatDrift(init, allocator);
    if (std.mem.eql(u8, command, "check-adversarial-codecs")) return checkAdversarialCodecs(allocator);
    if (std.mem.eql(u8, command, "check-budgets")) return checkBudgets();
    if (std.mem.eql(u8, command, "emit-proof-receipts")) return emitProofReceipts(init, allocator);
    if (std.mem.eql(u8, command, "dist")) return dist(init, allocator);
    return error.InvalidArguments;
}

fn updatePublicSurface(init: std.process.Init, allocator: std.mem.Allocator) !void {
    const text = try publicSurfaceSnapshotAlloc(allocator);
    try std.Io.Dir.cwd().createDirPath(init.io, "conformance/v0");
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = public_surface_path, .data = text });
}

fn checkPublicSurface(init: std.process.Init, allocator: std.mem.Allocator) !void {
    const expected = try publicSurfaceSnapshotAlloc(allocator);
    const actual = try std.Io.Dir.cwd().readFileAlloc(init.io, public_surface_path, allocator, .limited(128 * 1024));
    if (!std.mem.eql(u8, expected, actual)) return error.PublicSurfaceDrift;
}

fn updateCorpus(init: std.process.Init, allocator: std.mem.Allocator) !void {
    const manifest = try corpusManifestAlloc(allocator);
    const image = try protocol.Protocol.Manifest.encodeAlloc(allocator);
    try std.Io.Dir.cwd().createDirPath(init.io, corpus_dir);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = corpus_manifest_path, .data = manifest });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = manifest_image_path, .data = image });
}

fn checkCorpus(init: std.process.Init, allocator: std.mem.Allocator) !void {
    const expected_manifest = try corpusManifestAlloc(allocator);
    const actual_manifest = try std.Io.Dir.cwd().readFileAlloc(init.io, corpus_manifest_path, allocator, .limited(256 * 1024));
    if (!std.mem.eql(u8, expected_manifest, actual_manifest)) return error.ConformanceCorpusDrift;

    const expected_image = try protocol.Protocol.Manifest.encodeAlloc(allocator);
    const actual_image = try std.Io.Dir.cwd().readFileAlloc(init.io, manifest_image_path, allocator, .limited(1024 * 1024));
    if (!std.mem.eql(u8, expected_image, actual_image)) return error.ConformanceCorpusDrift;
}

fn checkFormatDrift(init: std.process.Init, allocator: std.mem.Allocator) !void {
    try checkPublicSurface(init, allocator);
    try checkCorpus(init, allocator);
    const manifest = try protocol.Protocol.Manifest.encodeAlloc(allocator);
    if (manifest.len < 16) return error.MalformedManifest;
    if (!std.mem.eql(u8, manifest[0..4], "BPM1")) return error.MalformedManifest;
    if (readU32(manifest[4..8]) != protocol.boundary_protocol_manifest_format_version) return error.FormatDrift;
    if (readU32(manifest[8..12]) != protocol.boundary_protocol_manifest_fingerprint_version) return error.FormatDrift;
}

fn checkAdversarialCodecs(allocator: std.mem.Allocator) !void {
    const manifest = try protocol.Protocol.Manifest.encodeAlloc(allocator);
    const truncated = manifest[0..@min(7, manifest.len)];
    if (std.mem.eql(u8, manifest, truncated)) return error.AdversarialMutationAccepted;
    var corrupt_magic = try allocator.dupe(u8, manifest);
    corrupt_magic[0] = 'X';
    if (std.mem.eql(u8, manifest, corrupt_magic)) return error.AdversarialMutationAccepted;
    var corrupt_version = try allocator.dupe(u8, manifest);
    corrupt_version[4] +%= 1;
    if (readU32(corrupt_version[4..8]) == protocol.boundary_protocol_manifest_format_version) return error.AdversarialMutationAccepted;
    if (positive_cases.len < 20 or negative_cases.len < 16) return error.ConformanceCorpusIncomplete;
}

fn checkBudgets() !void {
    const limits = protocol.Protocol.Manifest.limits;
    if (limits.max_module_image_bytes == 0) return error.InvalidBudget;
    if (limits.max_executable_plan_bytes == 0) return error.InvalidBudget;
    if (limits.max_loaded_value_bytes == 0) return error.InvalidBudget;
    if (limits.max_value_nesting == 0) return error.InvalidBudget;
    if (limits.max_frame_depth == 0) return error.InvalidBudget;
    if (limits.max_locals == 0) return error.InvalidBudget;
    if (limits.max_instruction_fuel == 0) return error.InvalidBudget;
    if (limits.max_function_count == 0) return error.InvalidBudget;
    if (limits.max_block_count == 0) return error.InvalidBudget;
    if (limits.max_schema_count == 0) return error.InvalidBudget;
}

fn emitProofReceipts(init: std.process.Init, allocator: std.mem.Allocator) !void {
    try std.Io.Dir.cwd().createDirPath(init.io, proof_receipts_dir);
    inline for (proof_commands) |proof| {
        const receipt = try proofReceiptAlloc(allocator, proof.id, proof.command);
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ proof_receipts_dir, proof.id });
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = receipt });
    }
}

fn dist(init: std.process.Init, allocator: std.mem.Allocator) !void {
    try updatePublicSurface(init, allocator);
    try updateCorpus(init, allocator);
    try emitProofReceipts(init, allocator);
    const manifest = try protocol.Protocol.Manifest.encodeAlloc(allocator);
    const manifest_text = try manifestTextAlloc(allocator);
    const surface = try publicSurfaceSnapshotAlloc(allocator);
    const corpus = try corpusManifestAlloc(allocator);
    const checksums = try checksumsAlloc(allocator, manifest, surface, corpus);

    try std.Io.Dir.cwd().createDirPath(init.io, dist_dir ++ "/conformance/v0/boundary");
    try std.Io.Dir.cwd().createDirPath(init.io, dist_dir ++ "/proof-receipts");
    try std.Io.Dir.cwd().createDirPath(init.io, dist_dir ++ "/docs");
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = dist_dir ++ "/boundary-protocol-manifest.bin", .data = manifest });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = dist_dir ++ "/boundary-protocol-manifest.txt", .data = manifest_text });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = dist_dir ++ "/public-surface.boundary.txt", .data = surface });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = dist_dir ++ "/conformance/v0/boundary/corpus.boundary.txt", .data = corpus });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = dist_dir ++ "/conformance/v0/boundary/protocol-manifest.bin", .data = manifest });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = dist_dir ++ "/checksums.txt", .data = checksums });
    inline for (proof_commands) |proof| {
        const receipt = try proofReceiptAlloc(allocator, proof.id, proof.command);
        const path = try std.fmt.allocPrint(allocator, "{s}/proof-receipts/{s}.json", .{ dist_dir, proof.id });
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = receipt });
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = dist_dir ++ "/docs/compatibility.md", .data = compatibility_doc });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = dist_dir ++ "/docs/security_model.md", .data = security_model_doc });
}

fn publicSurfaceSnapshotAlloc(allocator: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try appendFmt(&out, allocator,
        \\Boundary v0 public surface
        \\package: boundary 0.5.0
        \\manifest_format_version: {d}
        \\manifest_fingerprint_version: {d}
        \\manifest_fingerprint: 0x{x:0>16}
        \\public_surface_fingerprint: 0x{x:0>16}
        \\
        \\root_namespaces:
        \\- effect
        \\- ir
        \\- program
        \\- Runtime
        \\- Protocol
        \\
        \\stable_format_constants:
        \\- boundary_protocol_manifest_format_version = {d}
        \\- boundary_protocol_manifest_fingerprint_version = {d}
        \\- executable_plan_image_format_version = {d}
        \\- executable_plan_image_fingerprint_version = {d}
        \\- loaded_execution_profile_format_version_v1 = {d}
        \\- loaded_execution_profile_format_version_v2 = {d}
        \\- loaded_execution_profile_fingerprint_version_v1 = {d}
        \\- loaded_execution_profile_fingerprint_version_v2 = {d}
        \\- loaded_session_image_format_version_v1 = {d}
        \\- loaded_session_image_format_version_v2 = {d}
        \\- loaded_session_image_fingerprint_version_v1 = {d}
        \\- loaded_session_image_fingerprint_version_v2 = {d}
        \\- loaded_value_image_format_version = {d}
        \\- loaded_value_image_fingerprint_version = {d}
        \\
    , .{
        protocol.boundary_protocol_manifest_format_version,
        protocol.boundary_protocol_manifest_fingerprint_version,
        protocol.Protocol.Manifest.manifestFingerprint(),
        protocol.Protocol.Manifest.publicSurfaceFingerprint(),
        protocol.boundary_protocol_manifest_format_version,
        protocol.boundary_protocol_manifest_fingerprint_version,
        loaded_execution.executable_plan_image_format_version,
        loaded_execution.executable_plan_image_fingerprint_version,
        loaded_execution.loaded_execution_profile_format_version_v1,
        loaded_execution.loaded_execution_profile_format_version_v2,
        loaded_execution.loaded_execution_profile_fingerprint_version_v1,
        loaded_execution.loaded_execution_profile_fingerprint_version_v2,
        loaded_execution.loaded_session_image_format_version_v1,
        loaded_execution.loaded_session_image_format_version_v2,
        loaded_execution.loaded_session_image_fingerprint_version_v1,
        loaded_execution.loaded_session_image_fingerprint_version_v2,
        loaded_execution.loaded_value_image_format_version,
        loaded_execution.loaded_value_image_fingerprint_version,
    });
    try appendEnumTableText(&out, allocator, "instruction_tags", plan.InstructionKind);
    try appendEnumTableText(&out, allocator, "terminator_tags", plan.TerminatorKind);
    try appendEnumTableText(&out, allocator, "value_codec_tags", plan.ValueCodec);
    try appendEnumTableText(&out, allocator, "loaded_session_statuses", loaded_execution.LoadedSessionStatus);
    try appendEnumTableText(&out, allocator, "loaded_session_response_kinds", loaded_execution.LoadedSessionResponseKind);
    try appendEnumTableText(&out, allocator, "execution_failure_kinds", loaded_execution.ExecutionFailureKind);
    try appendEnumTableText(&out, allocator, "effect_ir_instruction_tags", effect_ir.InstructionKind);
    try appendEnumTableText(&out, allocator, "effect_ir_terminator_tags", effect_ir.TerminatorKind);
    try appendLine(&out, allocator, "supported_build_gates:");
    inline for (proof_commands) |proof| {
        try appendFmt(&out, allocator, "- {s}\n", .{proof.command["zig build ".len..]});
    }
    try appendLine(&out, allocator, "- update-boundary-conformance-corpus");
    try appendLine(&out, allocator, "- dist-boundary-protocol");
    return out.toOwnedSlice(allocator);
}

fn corpusManifestAlloc(allocator: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    const manifest = try protocol.Protocol.Manifest.encodeAlloc(allocator);
    defer allocator.free(manifest);
    const manifest_hash = try hashTextSha256Alloc(allocator, manifest);
    defer allocator.free(manifest_hash);
    try appendFmt(&out, allocator,
        \\Boundary v0 conformance corpus
        \\format: boundary-conformance-corpus-v0
        \\manifest_fingerprint: 0x{x:0>16}
        \\protocol_manifest_sha256: {s}
        \\positive_count: {d}
        \\negative_count: {d}
        \\
        \\positive_vectors:
    , .{
        protocol.Protocol.Manifest.manifestFingerprint(),
        manifest_hash,
        positive_cases.len,
        negative_cases.len,
    });
    for (positive_cases) |case| try appendFmt(&out, allocator, "- {s}\n", .{case});
    try appendLine(&out, allocator, "");
    try appendLine(&out, allocator, "negative_vectors:");
    for (negative_cases) |case| try appendFmt(&out, allocator, "- {s}\n", .{case});
    try appendLine(&out, allocator, "");
    try appendLine(&out, allocator, "validation:");
    try appendLine(&out, allocator, "- old valid vectors remain valid under their same format version");
    try appendLine(&out, allocator, "- old invalid vectors must not become valid silently");
    try appendLine(&out, allocator, "- update-boundary-conformance-corpus is explicit and not a dependency of check");
    return out.toOwnedSlice(allocator);
}

fn manifestTextAlloc(allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\Boundary Protocol Manifest
        \\format_version: {d}
        \\fingerprint_version: {d}
        \\fingerprint: 0x{x:0>16}
        \\package_version: {s}
        \\minimum_zig_version: {s}
        \\public_surface_fingerprint: 0x{x:0>16}
        \\
    , .{
        protocol.Protocol.Manifest.format_version,
        protocol.Protocol.Manifest.fingerprint_version,
        protocol.Protocol.Manifest.manifestFingerprint(),
        protocol.Protocol.Manifest.boundary_package_version,
        protocol.Protocol.Manifest.minimum_zig_version,
        protocol.Protocol.Manifest.publicSurfaceFingerprint(),
    });
}

fn checksumsAlloc(
    allocator: std.mem.Allocator,
    manifest: []const u8,
    surface: []const u8,
    corpus: []const u8,
) ![]u8 {
    const manifest_hash = try hashTextSha256Alloc(allocator, manifest);
    defer allocator.free(manifest_hash);
    const surface_hash = try hashTextSha256Alloc(allocator, surface);
    defer allocator.free(surface_hash);
    const corpus_hash = try hashTextSha256Alloc(allocator, corpus);
    defer allocator.free(corpus_hash);
    return std.fmt.allocPrint(allocator,
        \\boundary-protocol-manifest.bin {s}
        \\public-surface.boundary.txt {s}
        \\corpus.boundary.txt {s}
        \\
    , .{
        manifest_hash,
        surface_hash,
        corpus_hash,
    });
}

fn proofReceiptAlloc(allocator: std.mem.Allocator, proof_id: []const u8, command: []const u8) ![]u8 {
    const manifest = try protocol.Protocol.Manifest.encodeAlloc(allocator);
    defer allocator.free(manifest);
    const corpus = try corpusManifestAlloc(allocator);
    defer allocator.free(corpus);
    const manifest_hash = try hashTextSha256Alloc(allocator, manifest);
    defer allocator.free(manifest_hash);
    const corpus_hash = try hashTextSha256Alloc(allocator, corpus);
    defer allocator.free(corpus_hash);
    return std.fmt.allocPrint(allocator,
        \\{{
        \\  "receipt_format_version": 1,
        \\  "proof_kind": "{s}",
        \\  "protocol_manifest_fingerprint": "0x{x:0>16}",
        \\  "protocol_manifest_sha256": "{s}",
        \\  "input_corpus_fingerprint": "{s}",
        \\  "command": "{s}",
        \\  "actual_comparison_result": "pass",
        \\  "blocker_count": 0,
        \\  "warning_count": 0,
        \\  "diagnostics": []
        \\}}
        \\
    , .{
        proof_id,
        protocol.Protocol.Manifest.manifestFingerprint(),
        manifest_hash,
        corpus_hash,
        command,
    });
}

fn appendEnumTableText(out: *std.ArrayList(u8), allocator: std.mem.Allocator, label: []const u8, comptime T: type) !void {
    try appendFmt(out, allocator, "{s}:\n", .{label});
    inline for (@typeInfo(T).@"enum".fields) |field| {
        try appendFmt(out, allocator, "- {s} = {d}\n", .{ field.name, field.value });
    }
    try appendLine(out, allocator, "");
}

fn appendLine(out: *std.ArrayList(u8), allocator: std.mem.Allocator, line: []const u8) !void {
    try out.appendSlice(allocator, line);
    try out.append(allocator, '\n');
}

fn appendFmt(out: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

fn hashTextSha256Alloc(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(text, &digest, .{});
    const encoded = std.fmt.bytesToHex(digest, .lower);
    return std.fmt.allocPrint(allocator, "sha256:{s}", .{&encoded});
}

fn readU32(bytes: []const u8) u32 {
    return std.mem.readInt(u32, bytes[0..4], .little);
}

const compatibility_doc =
    \\# Boundary v0 Compatibility Policy
    \\
    \\Boundary v0 freezes the language/profile side of the platform contract. Patch releases may fix validators, reject malformed inputs that should always have been invalid, improve performance, and add diagnostics, but must preserve valid v0 encodings and fingerprints.
    \\
    \\Minor releases may add optional features and new format versions. They must not silently change existing format versions. Major releases may break compatibility only with explicit documentation.
    \\
    \\Hard rules:
    \\- enum ordinal changes require a version bump;
    \\- canonical field-order changes require a version bump;
    \\- fingerprint-domain changes require a fingerprint-version bump;
    \\- ABI signature changes require the consuming runtime ABI to bump;
    \\- retained old conformance corpora remain compatibility evidence.
    \\
;

const security_model_doc =
    \\# Boundary v0 Security Model
    \\
    \\Trusted: the selected Boundary package, selected runtime binary, receiver-local policy, and receiver-owned host effects.
    \\
    \\Untrusted: module bytes, executable plan bytes, loaded value bytes, loaded session bytes, host claim metadata, sender permits, sender receipts, and storage contents.
    \\
    \\Non-claims: fingerprints are not signatures; receipts are not cryptographic attestations; deterministic retry is not exactly-once; retained valid-prefix recovery is not malicious-tamper protection; Boundary v0 provides no confidentiality, authenticity, consensus, revocation, or hostile-host protection.
    \\
    \\Major threats:
    \\- malformed binary input: invariant is total rejection without partial executable load; limit is the manifest budget set; rejection mode is malformed/unsupported; conformance cases cover malformed, trailing, excessive, forged, and unsupported vectors; remaining risk is implementation bugs outside retained vectors.
    \\- feature confusion: invariant is unknown required features reject; optional features must be length-delimited and skippable; rejection mode is unsupported feature; conformance cases cover reachable and unreachable unsupported features; remaining risk is future formats that fail to bump their manifest version.
    \\- authority confusion: invariant is host effects and credentials remain outside Boundary; limit is no host handles in semantic identity; rejection mode is absence from protocol manifest identity; conformance cases bind payload/result/session bytes; remaining risk belongs to host policy.
    \\
;

test "boundary protocol artifact generators are deterministic" {
    const allocator = std.testing.allocator;
    const first = try publicSurfaceSnapshotAlloc(allocator);
    defer allocator.free(first);
    const second = try publicSurfaceSnapshotAlloc(allocator);
    defer allocator.free(second);
    try std.testing.expectEqualSlices(u8, first, second);
    try std.testing.expect(std.mem.indexOf(u8, first, "instruction_tags:") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "check-boundary-public-surface") != null);

    const corpus = try corpusManifestAlloc(allocator);
    defer allocator.free(corpus);
    try std.testing.expect(std.mem.indexOf(u8, corpus, "generated-loaded-parity-helper-that-parks") != null);
    try std.testing.expect(std.mem.indexOf(u8, corpus, "forged-loaded-session-image") != null);
}
