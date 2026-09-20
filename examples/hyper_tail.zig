//! History-free reciprocal countdown: no work follows the counterpart's answer.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const hyper = boundary.library.hyper;
const Id = source.Id;
fn decrement(b: *source.Builder, value: Id) !Id {
    return b.value(.{ .schema = try b.scalar(u64), .expression = .{ .primitive = .{ .opcode = .integer_sub, .operands = &.{ value, try b.constant(u64, 1) }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
}
const Step = struct {
    pub fn emit(b: *source.Builder, q: hyper.Query) !Id {
        const integer = try b.scalar(u64);
        const body = try b.declare(&.{}, integer, &.{}, &.{});
        const next = try b.variable(q.types.answer_backward);
        const delegate = try b.bind(next, try q.ask(b, try decrement(b, q.state)), try hyper.force(b, try b.reference(next)));
        const zero = try b.primitive(try b.scalar(bool), .equal, &.{ q.state, try b.constant(u64, 0) }, 0);
        try b.define(body, try b.term(.{ .conditional = .{ .condition = zero, .when_true = try b.pure(try b.constant(u64, 42)), .when_false = delegate } }));
        return b.pure(try b.lambda(body, q.types.answer_forward));
    }
};
const Application = struct {
    var direct = false;
    pub fn emit(b: *source.Builder) !source.Module {
        const integer = try b.scalar(u64);
        const entry = try b.declare(&.{integer}, integer, &.{}, &.{});
        const input = try b.reference(b.parameter(entry, 0));
        if (direct) {
            const zero = try b.primitive(try b.scalar(bool), .equal, &.{ input, try b.constant(u64, 0) }, 0);
            const next = try b.term(.{ .call = .{ .function = entry, .arguments = &.{try decrement(b, input)} } });
            try b.define(entry, try b.term(.{ .conditional = .{ .condition = zero, .when_true = try b.pure(try b.constant(u64, 42)), .when_false = next } }));
        } else {
            const types = try hyper.pairWith(b, integer, integer, &.{integer});
            const factory = try hyper.ana(b, types, integer, Step);
            const counterpart = try hyper.ana(b, hyper.swap(types), integer, Step);
            const left = try b.variable(types.forward);
            const right = try b.variable(types.backward);
            const peer = try b.declare(&.{}, types.backward, &.{}, &.{});
            try b.define(peer, try b.pure(try b.reference(right)));
            const result = try b.variable(types.answer_forward);
            const run = try b.bind(result, try hyper.invoke(b, try b.reference(left), try b.lambda(peer, types.peer_backward)), try hyper.force(b, try b.reference(result)));
            try b.define(entry, try b.bind(left, try hyper.start(b, factory, input), try b.bind(right, try hyper.start(b, counterpart, input), run)));
        }
        return b.module(entry, try b.scalar(void));
    }
};
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.MissingMode;
    if (args.next() != null) return error.UnexpectedArgument;
    Application.direct = std.mem.eql(u8, mode, "direct");
    if (!Application.direct and !std.mem.eql(u8, mode, "hyper")) return error.InvalidMode;
    var compiled = try boundary.program.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}
