//! The peer loops if demanded. Ordinary World execution must still return 42.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const hyper = boundary.library.hyper;

pub const Application = struct {
    var ignore_invocation = false;
    pub fn emit(b: *source.Builder) !source.Module {
        const integer = try b.scalar(u64);
        const unit = try b.scalar(void);
        const types = try hyper.pair(b, integer, integer);
        const answer = types.answer_forward;
        const value = try b.declare(&.{}, integer, &.{}, &.{});
        try b.define(value, try b.pure(try b.constant(u64, 42)));
        const constant = try b.declare(&.{types.peer_backward}, answer, &.{}, &.{});
        try b.define(constant, if (ignore_invocation) try b.term(.{ .call = .{
            .function = constant,
            .arguments = &.{try b.reference(b.parameter(constant, 0))},
        } }) else try b.pure(try b.lambda(value, answer)));
        const divergent = try b.declare(&.{}, types.backward, &.{}, &.{});
        try b.define(divergent, try b.term(.{ .call = .{
            .function = divergent,
            .arguments = &.{},
        } }));
        const entry = try b.declare(&.{}, integer, &.{}, &.{});
        const result = try b.variable(answer);
        const invoked = try hyper.invoke(b, try b.lambda(constant, types.forward), try b.lambda(divergent, types.peer_backward));
        const observed = if (ignore_invocation) try b.pure(try b.constant(u64, 42)) else try hyper.force(b, try b.reference(result));
        try b.define(entry, try b.bind(result, invoked, observed));
        return b.module(entry, unit);
    }
};

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    if (args.next()) |mode| {
        if (!std.mem.eql(u8, mode, "unused-invocation")) return error.InvalidArgument;
        Application.ignore_invocation = true;
    }
    if (args.next() != null) return error.InvalidArgument;
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
