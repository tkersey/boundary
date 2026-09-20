//! Two state-based participants retain distinct non-tail return computations.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const hyper = boundary.library.hyper;

fn step(b: *source.Builder, q: hyper.Query, stop: bool, increment: u64) !source.Id {
    const integer = try b.scalar(u64);
    const thunk = try b.declare(&.{}, integer, &.{}, &.{});
    const delayed = try b.variable(q.types.answer_backward);
    const answer = try b.variable(integer);
    const plus = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{
        .opcode = .integer_add,
        .operands = &.{ try b.reference(answer), try b.constant(u64, increment) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }},
    } } });
    const nested = try b.bind(delayed, try q.ask(b, try b.constant(bool, true)), try b.bind(answer, try hyper.force(b, try b.reference(delayed)), try b.pure(plus)));
    try b.define(thunk, if (stop) try b.term(.{ .conditional = .{
        .condition = q.state,
        .when_true = try b.pure(try b.constant(u64, 19)),
        .when_false = nested,
    } }) else nested);
    return b.pure(try b.lambda(thunk, q.types.answer_forward));
}
const Producer = struct {
    pub fn emit(b: *source.Builder, q: hyper.Query) !source.Id {
        return step(b, q, false, 10);
    }
};
const Consumer = struct {
    pub fn emit(b: *source.Builder, q: hyper.Query) !source.Id {
        return step(b, q, true, 13);
    }
};
const Application = struct {
    pub fn emit(b: *source.Builder) !source.Module {
        const integer = try b.scalar(u64);
        const boolean = try b.scalar(bool);
        const types = try hyper.pairWith(b, integer, integer, &.{boolean});
        const producer = try hyper.ana(b, types, boolean, Producer);
        const consumer = try hyper.ana(b, hyper.swap(types), boolean, Consumer);
        const entry = try b.declare(&.{}, integer, &.{}, &.{});
        const p = try b.variable(types.forward);
        const c = try b.variable(types.backward);
        const result = try b.variable(types.answer_backward);
        const peer = try b.declare(&.{}, types.forward, &.{}, &.{});
        try b.define(peer, try b.pure(try b.reference(p)));
        const invoke = try hyper.invoke(b, try b.reference(c), try b.lambda(peer, types.peer_forward));
        const answer = try b.bind(result, invoke, try hyper.force(b, try b.reference(result)));
        const body = try b.bind(c, try hyper.start(b, consumer, try b.constant(bool, false)), answer);
        try b.define(entry, try b.bind(p, try hyper.start(b, producer, try b.constant(bool, false)), body));
        return b.module(entry, try b.scalar(void));
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
