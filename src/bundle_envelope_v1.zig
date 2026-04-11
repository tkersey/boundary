const artifact = @import("shift_shared").artifact;
const std = @import("std");

/// One exact-build handoff envelope carrying ArtifactV1 bytes.
pub const BundleEnvelopeV1 = struct {
    build_fingerprint_blake3_256: [32]u8,
    artifact_hash_blake3_256: [32]u8,
    artifact_bytes: []u8,

    /// Release the owned artifact payload held by this envelope.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.artifact_bytes);
        self.* = undefined;
    }
};

/// Fail-closed import errors for BundleEnvelopeV1 payloads.
pub const BundleImportError = error{
    ArtifactHashMismatch,
    BadMagic,
    BuildFingerprintMismatch,
    InvalidArtifact,
    InvalidLength,
    UnsupportedVersion,
};

/// Export ArtifactV1 bytes into one exact-build bundle envelope.
pub fn exportBundle(
    allocator: std.mem.Allocator,
    artifact_bytes: []const u8,
) ![]u8 {
    var decoded = try artifact.decode(allocator, artifact_bytes);
    defer decoded.deinit(allocator);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "SFTBNDV1");
    try appendU16(&out, allocator, 1);
    try appendU16(&out, allocator, 0);
    try out.appendSlice(allocator, &decoded.build_fingerprint_blake3_256);
    try out.appendSlice(allocator, &decoded.artifact_hash_blake3_256);
    try appendU64(&out, allocator, @intCast(artifact_bytes.len));
    try out.appendSlice(allocator, artifact_bytes);
    return out.toOwnedSlice(allocator);
}

/// Import one exact-build bundle envelope and reject mismatched build fingerprints.
pub fn importBundle(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    expected_build_fingerprint: [32]u8,
) (BundleImportError || std.mem.Allocator.Error)!BundleEnvelopeV1 {
    const header_len: usize = 84;
    if (bytes.len < header_len) return error.InvalidLength;
    if (!std.mem.eql(u8, bytes[0..8], "SFTBNDV1")) return error.BadMagic;
    if (readU16(bytes, 8) != 1) return error.UnsupportedVersion;
    if (readU16(bytes, 10) != 0) return error.UnsupportedVersion;

    var build_fingerprint = std.mem.zeroes([32]u8);
    @memcpy(&build_fingerprint, bytes[12..44]);
    if (!std.mem.eql(u8, &build_fingerprint, &expected_build_fingerprint)) return error.BuildFingerprintMismatch;

    var artifact_hash = std.mem.zeroes([32]u8);
    @memcpy(&artifact_hash, bytes[44..76]);
    const artifact_len = std.math.cast(usize, readU64(bytes, 76)) orelse return error.InvalidLength;
    const total_len = std.math.add(usize, header_len, artifact_len) catch return error.InvalidLength;
    if (total_len != bytes.len) return error.InvalidLength;

    const artifact_bytes = try allocator.dupe(u8, bytes[header_len..]);
    errdefer allocator.free(artifact_bytes);

    var decoded = artifact.decode(allocator, artifact_bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidArtifact,
    };
    defer decoded.deinit(allocator);
    if (!std.mem.eql(u8, &decoded.build_fingerprint_blake3_256, &build_fingerprint)) return error.BuildFingerprintMismatch;
    if (!std.mem.eql(u8, &decoded.artifact_hash_blake3_256, &artifact_hash)) return error.ArtifactHashMismatch;

    return .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .artifact_hash_blake3_256 = artifact_hash,
        .artifact_bytes = artifact_bytes,
    };
}

fn appendU16(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    var buffer: [2]u8 = undefined;
    std.mem.writeInt(u16, &buffer, value, .little);
    try list.appendSlice(allocator, &buffer);
}

fn appendU64(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, value, .little);
    try list.appendSlice(allocator, &buffer);
}

fn readU16(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .little);
}

fn readU64(bytes: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, bytes[offset..][0..8], .little);
}
