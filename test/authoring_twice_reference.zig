//! Frozen low-level twice construction from the accepted baseline, kept independent.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
fn build(b: *source.Builder) !source.Module {
    const integer = try b.scalar(u64);
    const unit = try b.scalar(void);
    const lookup = try b.effect(.{ .identity = "case/lookup", .payload = integer, .result = integer });
    const computation = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = integer,
        .effects = &.{lookup},
    } } });
    const work = try b.declare(&.{}, integer, &.{lookup}, &.{});
    try b.define(work, try b.term(.{ .perform = .{ .effect = lookup, .payload = try b.constant(u64, 19) } }));
    const pair = try b.schema(.{ .product = &.{ integer, integer } });
    const twice = try b.declare(&.{computation}, pair, &.{lookup}, &.{});
    const callable = try b.reference(b.parameter(twice, 0));
    const first = try b.variable(integer);
    const second = try b.variable(integer);
    const apply = try b.term(.{ .apply = .{ .computation = callable, .arguments = &.{} } });
    const result = try b.primitive(pair, .product, &.{ try b.reference(first), try b.reference(second) }, 0);
    try b.define(twice, try b.bind(first, apply, try b.bind(second, apply, try b.pure(result))));
    const entry = try b.declare(&.{}, pair, &.{lookup}, &.{});
    try b.define(entry, try b.term(.{ .call = .{ .function = twice, .arguments = &.{try b.lambda(work, computation)} } }));
    return b.module(entry, unit);
}
pub fn main(init: std.process.Init) !void {
    var raw = source.Builder.init(init.gpa);
    defer raw.deinit();
    const module = try build(&raw);
    var args = init.minimal.args.iterate();
    _ = args.next();
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (args.next()) |_| {
        try std.json.Stringify.value(module, .{ .emit_strings_as_arrays = true }, &output.interface);
    } else {
        var compiled = try source.lower(init.gpa, module);
        defer compiled.deinit();
        const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
        defer init.gpa.free(bytes);
        _ = try compiled.encode(init.gpa, bytes);
        try output.interface.writeAll(bytes);
    }
    try output.interface.flush();
}
