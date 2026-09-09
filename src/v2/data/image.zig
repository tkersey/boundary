// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const p = @import("program.zig");
const wire = @import("wire.zig");
const record = @import("record.zig");
const admission = @import("admission.zig");
pub const Error = admission.Error || error{ InvalidDirectory, InvalidBuffers };
const fields = std.meta.fields(p.Program);
pub const section_count = 9;
comptime {
    std.debug.assert(fields.len == section_count);
}

fn lengths(program: p.Program) Error![section_count]usize {
    var sizes: [section_count]usize = undefined;
    inline for (fields, 0..) |field, index| {
        var writer: wire.Writer = .{};
        try record.write(field.type, @field(program, field.name), &writer);
        sizes[index] = writer.position;
    }
    return sizes;
}

fn directory(sizes: [section_count]usize, writer: *wire.Writer) Error!void {
    try writer.natural(section_count);
    var offset: usize = 0;
    for (sizes, 0..) |size, index| {
        try writer.natural(index + 1);
        try writer.natural(offset);
        try writer.natural(size);
        offset = std.math.add(usize, offset, size) catch return error.InvalidLength;
    }
}

pub fn encodedLength(program: p.Program) Error!usize {
    const sizes = try lengths(program);
    var writer: wire.Writer = .{};
    try directory(sizes, &writer);
    var total = std.math.add(usize, wire.header_length, writer.position) catch return error.InvalidLength;
    for (sizes) |size| total = std.math.add(usize, total, size) catch return error.InvalidLength;
    return total;
}

/// Identity of admitted canonical records, independent of evaluator and storage.
/// Normalize hand-built records with canonical.normalize before deriving IDs.
pub fn identity(program: p.Program) Error![32]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("boundary.program-image/v2");
    var buffer: [10]u8 = undefined;
    var ordinal: wire.Writer = .{ .output = &buffer };
    try ordinal.natural(program.roots.profile);
    wire.hashField(&hash, buffer[0..ordinal.position]);
    const sizes = try lengths(program);
    inline for (fields, 0..) |field, index| {
        ordinal.position = 0;
        try ordinal.natural(index + 1);
        wire.hashField(&hash, buffer[0..ordinal.position]);
        var writer: wire.Writer = .{ .hasher = &hash };
        try writer.natural(sizes[index]);
        try record.write(field.type, @field(program, field.name), &writer);
    }
    return hash.finalResult();
}

/// The caller owns output. All checks and sizing precede the first write.
pub fn encode(allocator: std.mem.Allocator, program: p.Program, output: []u8) Error![]const u8 {
    try @import("canonical.zig").require(allocator, program);
    const length = try encodedLength(program);
    if (output.len < length) return error.Capacity;
    if (record.overlaps(p.Program, program, output[0..length])) return error.InvalidBuffers;
    const sizes = try lengths(program);
    var writer: wire.Writer = .{ .output = output[0..length] };
    try writer.put(wire.magic(.bpi));
    try writer.fixed(u16, 2);
    try writer.fixed(u16, 0);
    try writer.fixed(u64, length - wire.header_length);
    try directory(sizes, &writer);
    inline for (fields) |field| try record.write(field.type, @field(program, field.name), &writer);
    return output[0..writer.position];
}

pub const Decoded = struct {
    arena: std.heap.ArenaAllocator,
    program: p.Program,
    bytes: []const u8,

    /// Releases the decoded records and their complete backing byte storage.
    pub fn deinit(self: *Decoded) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn decode(allocator: std.mem.Allocator, input: []const u8) Error!Decoded {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const owned = try arena.allocator().dupe(u8, input);
    const body = try wire.unframe(.bpi, owned);
    var reader: wire.Reader = .{ .input = body };
    if (try reader.natural() != section_count) return error.InvalidDirectory;
    var sizes: [section_count]usize = undefined;
    var end: usize = 0;
    for (&sizes, 0..) |*size, index| {
        if (try reader.natural() != index + 1) return error.InvalidDirectory;
        if (try reader.natural() != end) return error.InvalidDirectory;
        size.* = try reader.count();
        end = std.math.add(usize, end, size.*) catch return error.InvalidDirectory;
    }
    if (end != body.len - reader.position) return error.InvalidDirectory;
    var program: p.Program = undefined;
    inline for (fields, 0..) |field, index| {
        var section: wire.Reader = .{ .input = try reader.take(sizes[index]) };
        @field(program, field.name) = try record.read(field.type, &section, arena.allocator());
        try section.finish();
    }
    try reader.finish();
    try @import("canonical.zig").require(arena.allocator(), program);
    return .{ .arena = arena, .program = program, .bytes = owned };
}
