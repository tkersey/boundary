//! The peer loops if demanded. Ordinary World execution must still return 42.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const hyper = boundary.library.hyper;

pub const Application = struct {
    pub fn emit(b: *source.Builder) !source.Module {
        const integer = try b.scalar(u64);
        const unit = try b.scalar(void);
        const types = try hyper.pair(b, integer, integer);
        const answer = try hyper.delayed(b, integer, &.{});
        const value = try b.declare(&.{}, integer, &.{}, &.{});
        try b.define(value, try b.pure(try b.constant(u64, 42)));
        const constant = try b.declare(&.{types.peer_backward}, answer, &.{}, &.{});
        try b.define(constant, try b.pure(try b.lambda(value, answer)));
        const divergent = try b.declare(&.{}, types.backward, &.{}, &.{});
        try b.define(divergent, try b.term(.{ .call = .{
            .function = divergent,
            .arguments = &.{},
        } }));
        const entry = try b.declare(&.{}, integer, &.{}, &.{});
        const result = try b.variable(answer);
        const invoked = try hyper.invoke(b, try b.lambda(constant, types.forward), try b.lambda(divergent, types.peer_backward));
        try b.define(entry, try b.bind(result, invoked, try hyper.force(b, try b.reference(result))));
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
