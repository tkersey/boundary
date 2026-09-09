//! Public staged source for physical input/working/output arena exhaustion.
const std = @import("std");
const boundary = @import("boundary");
const Application = struct {
    pub fn emit(b: *boundary.computation.Builder) !boundary.computation.Module {
        const bytes = try b.schema(.bytes);
        const unit = try b.scalar(void);
        const effect = try b.effect(.{ .identity = "capacity.bytes.v2", .payload = bytes, .result = unit });
        const entry = try b.declare(&.{bytes}, bytes, &.{effect}, &.{});
        const argument = try b.reference(b.parameter(entry, 0));
        const ignored = try b.variable(unit);
        const request = try b.term(.{ .perform = .{ .effect = effect, .payload = argument } });
        try b.define(entry, try b.bind(ignored, request, try b.pure(argument)));
        return b.module(entry, unit);
    }
};
pub fn main(init: std.process.Init) !void {
    var compiled = try boundary.program.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.image_v2.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
