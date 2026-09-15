// Copyright (c) 2026 Boundary contributors. MIT license.
//! Opt-in packed canonical images. Existing image.encode always produces BPI2.
const std = @import("std");
const p = @import("program.zig");
const wire = @import("wire.zig");
const record = @import("record.zig");
const packed_record = @import("compact_record.zig");
const canonical = @import("canonical.zig");
const image = @import("image.zig");
const parameters = @import("compact_parameters.zig");
const sequence = @import("compact_sequence.zig");
pub const Error = image.Error;
pub const Decoded = image.Decoded;
pub const magic = "ABL_BPC1";

pub fn isCompact(input: []const u8) bool {
    return input.len >= magic.len and std.mem.eql(u8, input[0..magic.len], magic);
}

fn packedLength(program: p.Program, plan: *const parameters.Plan) Error!usize {
    var writer: wire.Writer = .{ .position = wire.header_length };
    try writeProgram(program, plan, &writer);
    return writer.position;
}

fn writeProgram(program: p.Program, plan: *const parameters.Plan, writer: *wire.Writer) Error!void {
    try writer.natural(plan.backings.items.len);
    for (plan.backings.items) |values| try sequence.write(p.Id, values, writer);
    var context: parameters.Writing = .{ .plan = plan };
    try packed_record.write(p.Program, program, writer, &context);
}

/// Exact selected size, including framing. Like legacy sizing, this grants no
/// admission; encode always checks the current mutable public records itself.
pub fn encodedLength(allocator: std.mem.Allocator, program: p.Program) Error!usize {
    var plan = try parameters.Plan.init(allocator, program);
    defer plan.deinit();
    return @min(try packedLength(program, &plan), try image.encodedLength(program));
}

/// The returned slice borrows output. Checks and fallible preparation precede writes.
/// Ties and larger packed representations select the exact legacy BPI2 bytes.
pub fn encode(allocator: std.mem.Allocator, program: p.Program, output: []u8) Error![]const u8 {
    try canonical.require(allocator, program);
    var plan = try parameters.Plan.init(allocator, program);
    defer plan.deinit();
    const packed_length = try packedLength(program, &plan);
    const legacy_length = try image.encodedLength(program);
    const length = @min(packed_length, legacy_length);
    if (output.len < length) return error.Capacity;
    if (record.overlaps(p.Program, program, output[0..length])) return error.InvalidBuffers;
    if (legacy_length <= packed_length) return image.encode(allocator, program, output);
    var writer: wire.Writer = .{ .output = output[0..length] };
    try writer.put(magic);
    try writer.fixed(u16, 1);
    try writer.fixed(u16, 0);
    try writer.fixed(u64, length - wire.header_length);
    try writeProgram(program, &plan, &writer);
    std.debug.assert(writer.position == length);
    return output[0..length];
}

fn body(input: []const u8) Error![]const u8 {
    var reader: wire.Reader = .{ .input = input };
    if (!std.mem.eql(u8, try reader.take(8), magic)) return error.InvalidFamily;
    if (try reader.fixed(u16) != 1) return error.UnsupportedVersion;
    if (try reader.fixed(u16) != 0) return error.InvalidFlags;
    const length = try reader.fixed(u64);
    if (length != input.len - wire.header_length) return error.InvalidLength;
    return input[wire.header_length..];
}

/// Accepts either selected format; malformed BPC1 never falls back to BPI2.
/// All returned records and bytes belong to Decoded.arena, independent of input.
pub fn decode(allocator: std.mem.Allocator, input: []const u8) Error!Decoded {
    if (!isCompact(input)) return image.decode(allocator, input);
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const owned = try arena.allocator().dupe(u8, input);
    var reader: wire.Reader = .{ .input = try body(owned) };
    var requested = owned.len;
    const count = try reader.count();
    if (count > reader.input.len - reader.position) return error.Truncated;
    try sequence.account([]const p.Id, count, &requested);
    const backings = try arena.allocator().alloc([]const p.Id, count);
    for (backings) |*values|
        values.* = try sequence.read(p.Id, true, &reader, arena.allocator(), &requested);
    const program = blk: {
        const fully_used = try allocator.alloc(bool, count);
        defer allocator.free(fully_used);
        @memset(fully_used, false);
        const program = try packed_record.read(p.Program, &reader, arena.allocator(), &requested, .{ .backings = backings, .fully_used = fully_used });
        for (fully_used) |used| if (!used) return error.NonCanonical;
        break :blk program;
    };
    try reader.finish();
    for (backings) |values| for (values) |schema| {
        if (schema >= program.schemas.len) return error.InvalidLength;
    };
    try canonical.require(allocator, program);
    return .{ .arena = arena, .program = program, .bytes = owned };
}
