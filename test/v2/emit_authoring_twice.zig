//! Independent low-level caller of the migrated public twice combinator.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;

const Application = struct {
    pub fn emit(b: *source.Builder) !source.Module {
        const integer = try b.scalar(u64);
        const unit = try b.scalar(void);
        const lookup = try b.effect(.{ .identity = "twice/lookup", .payload = integer, .result = integer });
        const callable = try b.schema(.{ .internal = .{ .computation = .{
            .parameters = &.{},
            .result = integer,
            .effects = &.{lookup},
            .use = .reusable,
        } } });
        const twice = try boundary.library.combinators.twice(b, callable);
        const pair = try b.schema(.{ .product = &.{ integer, integer } });
        const callback = try b.declare(&.{}, integer, &.{lookup}, &.{});
        try b.define(callback, try b.term(.{ .perform = .{ .effect = lookup, .payload = try b.constant(u64, 5) } }));
        const entry = try b.declare(&.{}, pair, &.{lookup}, &.{});
        try b.define(entry, try b.term(.{ .call = .{ .function = twice, .arguments = &.{try b.lambda(callback, callable)} } }));
        return b.module(entry, unit);
    }
};

pub fn main(init: std.process.Init) !void {
    var compiled = try boundary.program.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
