//! Reciprocal ana steps expressed using lexical internal Need effects.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const hyper = boundary.library.hyper;
const Id = source.Id;
const Types = struct {
    integer: Id,
    boolean: Id,
    task: Id,
    pair: hyper.Pair,
    read: Id,
    producer: hyper.demand.Family,
    consumer: hyper.demand.Family,
};
fn types(b: *source.Builder) !Types {
    const cache = try b.specialization(Types, "example.hyper-demand/v1", .{});
    if (cache.cached) |value| return value;
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const read = try b.effect(.{ .identity = "hyper/reference", .payload = integer, .result = integer });
    const task = try b.reserveSchema();
    const pair = try hyper.pairWith(b, task, task, &.{ integer, boolean });
    try b.defineSchema(task, .{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = integer,
        .effects = &.{read},
        .capture_bound = &.{ boolean, pair.peer_forward, pair.peer_backward },
    } } });
    return cache.finish(b, .{ .integer = integer, .boolean = boolean, .task = task, .pair = pair, .read = read, .producer = try hyper.demand.family(b, "hyper/need", boolean, integer), .consumer = try hyper.demand.family(b, "hyper/need", boolean, integer) });
}
fn step(b: *source.Builder, q: hyper.Query, consumer: bool) !Id {
    const t = try types(b);
    const need = if (consumer) t.consumer else t.producer;
    const interpretation = try hyper.demand.interpret(b, q, need, t.integer, .{
        .captures = &.{ t.boolean, t.integer, t.pair.peer_forward, t.pair.peer_backward },
        .residual = .{ .effects = &.{t.read} },
    });
    const body = try b.declare(&.{need.capability}, t.integer, &.{ t.read, need.effect }, &.{});
    const contribution = try b.variable(t.integer);
    const plus = try b.value(.{ .schema = t.integer, .expression = .{ .primitive = .{
        .opcode = .integer_add,
        .operands = &.{ try b.reference(contribution), try b.constant(u64, if (consumer) 13 else 10) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }},
    } } });
    const query = try hyper.demand.request(b, need, try b.reference(b.parameter(body, 0)), try b.constant(bool, true));
    const nested = try b.bind(contribution, query, try b.pure(plus));
    try b.define(body, if (consumer) try b.term(.{ .conditional = .{
        .condition = q.state,
        .when_true = try b.term(.{ .perform = .{ .effect = t.read, .payload = try b.constant(u64, 19) } }),
        .when_false = nested,
    } }) else nested);
    const task = try b.declare(&.{}, t.integer, &.{t.read}, &.{});
    try b.define(task, try hyper.demand.handle(b, interpretation, q.peer, try b.lambda(body, interpretation.body)));
    const descriptor = try b.declare(&.{}, t.task, &.{}, &.{});
    try b.define(descriptor, try b.pure(try b.lambda(task, t.task)));
    return b.pure(try b.lambda(descriptor, q.types.answer_forward));
}
const Producer = struct {
    pub fn emit(b: *source.Builder, q: hyper.Query) !Id {
        return step(b, q, false);
    }
};
const Consumer = struct {
    pub fn emit(b: *source.Builder, q: hyper.Query) !Id {
        return step(b, q, true);
    }
};
const Application = struct {
    pub fn emit(b: *source.Builder) !source.Module {
        const t = try types(b);
        const producer = try hyper.ana(b, t.pair, t.boolean, Producer);
        const consumer = try hyper.ana(b, hyper.swap(t.pair), t.boolean, Consumer);
        const entry = try b.declare(&.{}, t.integer, &.{t.read}, &.{});
        const p = try b.variable(t.pair.forward);
        const c = try b.variable(t.pair.backward);
        const peer = try b.declare(&.{}, t.pair.forward, &.{}, &.{});
        try b.define(peer, try b.pure(try b.reference(p)));
        const delayed = try b.variable(t.pair.answer_backward);
        const task = try b.variable(t.task);
        const run = try b.bind(delayed, try hyper.invoke(b, try b.reference(c), try b.lambda(peer, t.pair.peer_forward)), try b.bind(task, try hyper.force(b, try b.reference(delayed)), try hyper.force(b, try b.reference(task))));
        const started = try b.bind(c, try hyper.start(b, consumer, try b.constant(bool, false)), run);
        try b.define(entry, try b.bind(p, try hyper.start(b, producer, try b.constant(bool, false)), started));
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
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}
