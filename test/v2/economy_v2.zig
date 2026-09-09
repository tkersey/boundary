//! Matched source, checking, lowering and emission workloads for Boundary 2.
const std = @import("std");
const boundary = @import("boundary");
const options = @import("economy_options");

pub fn main(init: std.process.Init) !void {
    var b = boundary.computation.Builder.init(init.gpa);
    defer b.deinit();
    const integer = try b.scalar(if (options.kind == 0) u32 else u64);
    const failure = try b.schema(.{ .enumeration = &.{0} });
    const effect: ?u64 = if (options.kind == 0) try b.effect(.{ .identity = "example.lookup.v1", .payload = integer, .result = integer }) else null;
    const entry = try b.declare(&.{integer}, integer, if (effect) |id| &.{id} else &.{}, &.{});
    var value = try b.reference(b.parameter(entry, 0));
    if (effect) |id| {
        try b.define(entry, try b.term(.{ .perform = .{ .effect = id, .payload = value } }));
    } else {
        const one = try b.constant(u64, 1);
        const fault = try b.failureLiteral(try b.literal(.{ .schema = failure, .bytes = &.{ 0, 0, 0, 0 } }));
        for (0..32) |_| value = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ value, one }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = fault }} } } });
        try b.define(entry, try b.pure(value));
    }
    var compiled = try boundary.program.compile(init.gpa, b.module(entry, failure));
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.image_v2.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
