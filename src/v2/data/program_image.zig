// Copyright (c) 2026 Boundary contributors. MIT license.
//! The successor image encodes stable records directly, with no legacy fallback.
const std = @import("std");
const ir = @import("activation.zig");
const wire = @import("wire.zig");
const record = @import("record.zig");
const body_record = @import("program_record.zig");
const admission = @import("activation_ownership.zig");
pub const Error = admission.Error || body_record.Error;
pub const magic = "ABL_BPI3";
pub const identity_domain = "boundary.program/v3\x00";
pub const Limits = struct { max_decoded_bytes: usize = 64 << 20 };

pub fn encodedLength(program: ir.Program) Error!usize {
    var writer: wire.Writer = .{ .position = wire.header_length };
    var context: body_record.Context = .{};
    try body_record.write(ir.Program, program, &writer, &context);
    return writer.position;
}

fn write(program: ir.Program, length: usize, writer: *wire.Writer) Error!void {
    try writer.put(magic);
    try writer.fixed(u16, 3);
    try writer.fixed(u16, 0);
    try writer.fixed(u64, length - wire.header_length);
    var context: body_record.Context = .{};
    try body_record.write(ir.Program, program, writer, &context);
}

/// Full admission, sizing and overlap checks precede the first output write.
pub fn encode(allocator: std.mem.Allocator, program: ir.Program, output: []u8) Error![]const u8 {
    var checked = try admission.analyze(allocator, program);
    defer checked.deinit();
    const length = try encodedLength(program);
    if (output.len < length) return error.Capacity;
    if (record.overlaps(ir.Program, program, output[0..length])) return error.InvalidBuffers;
    var writer: wire.Writer = .{ .output = output[0..length] };
    try write(program, length, &writer);
    std.debug.assert(writer.position == length);
    return output[0..length];
}

/// Domain-separated identity over the admitted compact structural encoding.
pub fn identity(allocator: std.mem.Allocator, program: ir.Program) Error![32]u8 {
    var checked = try admission.analyze(allocator, program);
    defer checked.deinit();
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(identity_domain);
    var writer: wire.Writer = .{ .hasher = &hash };
    try write(program, try encodedLength(program), &writer);
    return hash.finalResult();
}

pub const Decoded = struct {
    arena: std.heap.ArenaAllocator,
    program: ir.Program,
    bytes: []const u8,
    identity: [32]u8,
    decoded_bytes: usize,

    pub fn deinit(self: *Decoded) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn decode(allocator: std.mem.Allocator, input: []const u8) Error!Decoded {
    return decodeLimited(allocator, input, .{});
}

pub fn decodeLimited(allocator: std.mem.Allocator, input: []const u8, limits: Limits) Error!Decoded {
    if (input.len < wire.header_length) return error.Truncated;
    if (input.len > limits.max_decoded_bytes) return error.Capacity;
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const owned = try arena.allocator().dupe(u8, input);
    var reader: wire.Reader = .{ .input = owned };
    if (!std.mem.eql(u8, try reader.take(8), magic)) return error.InvalidFamily;
    if (try reader.fixed(u16) != 3) return error.UnsupportedVersion;
    if (try reader.fixed(u16) != 0) return error.InvalidFlags;
    if (try reader.fixed(u64) != owned.len - wire.header_length) return error.InvalidLength;
    var context: body_record.Context = .{};
    var budget: body_record.Budget = .{ .used = owned.len, .maximum = limits.max_decoded_bytes };
    const program = try body_record.read(ir.Program, &reader, arena.allocator(), &budget, &context);
    try reader.finish();
    var checked = try admission.analyze(allocator, program);
    defer checked.deinit();
    // Re-emission checks every omitted default and compressed spelling. The hash
    // receives those same bytes; neither path expands old live interfaces.
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(identity_domain);
    var canonical: wire.Writer = .{ .expected = owned, .hasher = &hash };
    try write(program, owned.len, &canonical);
    if (canonical.position != owned.len) return error.NonCanonical;
    return .{ .arena = arena, .program = program, .bytes = owned, .identity = hash.finalResult(), .decoded_bytes = budget.used };
}
