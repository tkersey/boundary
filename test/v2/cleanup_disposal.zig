//! Authored variants of the writer/raise fixture that abandon a running cleanup.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.source;
const p = boundary.data_v2.program;

pub const Mode = enum { always, running, failure };

fn handlerFor(b: *source.Builder, identity: []const u8) source.Error!p.Handler {
    for (b.handlers.items) |handler| {
        if (handler.clauses.len == 1 and std.mem.eql(u8, b.effects.items[@intCast(handler.clauses[0].effect)].identity, identity)) return handler;
    }
    return error.InvalidSource;
}

fn appendLog(b: *source.Builder, cell: p.Id, message: p.Id) source.Error!p.Id {
    const cell_type = b.schemas.items[@intCast(b.values.items[@intCast(cell)].schema)].internal.cell;
    const before = try b.primitive(cell_type.element, .cell_get, &.{cell}, 0);
    const after = try b.primitive(cell_type.element, .sequence_append, &.{ before, message }, 0);
    return b.pure(try b.primitive(try b.scalar(void), .cell_set, &.{ cell, after }, 0));
}

pub fn build(b: *source.Builder, mode: Mode) source.Error!source.ast.Module {
    const original = try source.examples.writerRaise(b);
    const handler = try handlerFor(b, "example/writer");
    const clause = handler.clauses[0].function;
    const body = b.terms.items[@intCast(b.functions.items[@intCast(clause)].body.?)].bind;
    const unit = try b.scalar(void);
    const cell = try b.reference(b.parameter(clause, 0));
    const message = try b.reference(b.parameter(clause, 1));
    const token = try b.reference(b.parameter(clause, 2));
    const result = try b.primitive(handler.input, .variant, &.{message}, 1);
    const answer = try b.term(.{ .call = .{
        .function = handler.return_function,
        .arguments = &.{ cell, result },
    } });
    const marked = try b.bind(try b.variable(unit), try appendLog(b, cell, try b.constant(u64, 99)), answer);
    const disposed = try b.bind(try b.variable(unit), try b.term(.{ .dispose = token }), marked);
    const selected = if (mode == .always) disposed else selected: {
        const condition = try b.primitive(try b.scalar(bool), .equal, &.{ message, try b.constant(u64, 3) }, 0);
        break :selected try b.term(.{ .conditional = .{
            .condition = condition,
            .when_true = disposed,
            .when_false = body.next,
        } });
    };
    b.functions.items[@intCast(clause)].body = try b.bind(try b.variable(unit), body.value, selected);
    if (mode == .failure) {
        const raised = try handlerFor(b, "example/raise");
        const failure = try b.constant(void, {});
        for (b.terms.items) |*term| {
            if (term.* == .perform and term.perform.effect == raised.clauses[0].effect)
                term.* = .{ .fail = failure };
        }
        for (b.terms.items) |term| {
            if (term != .protect) continue;
            const finalizer = b.values.items[@intCast(term.protect.cleanup)].expression.lambda;
            const previous = b.functions.items[@intCast(finalizer)].body.?;
            b.functions.items[@intCast(finalizer)].body = try b.term(.{ .yield_then = previous });
            break;
        }
    }
    return b.module(original.entry, original.failure);
}

/// The protected body returns an owned generator. Abandoning its cleanup must
/// close that generator and execute its pending finalizer before the clause ends.
pub fn ownedResult(b: *source.Builder) source.Error!source.ast.Module {
    const writer = boundary.library.writer;
    const generator = boundary.library.generator;
    const cleanup = boundary.library.cleanup;
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const region = b.region();
    const region_type = try b.schema(.{ .internal = .{ .region = region } });
    const w = try writer.family(b, "example/cleanup-owner-writer", integer);
    const g = try generator.defineScoped(b, "example/cleanup-owned-yield", integer, &.{ unit, integer, w.capability }, &.{}, &.{region}, .{ .effects = &.{w.effect} });
    const written = try writer.interpret(b, w, integer, region, &.{ unit, integer, g.capability, g.answer, g.resumption, g.package, g.yielded }, .{ .effects = &.{} });
    const main = try b.declare(&.{}, written.answer, &.{}, &.{});
    const inside = try b.declare(&.{region_type}, written.answer, &.{}, &.{region});
    const written_body = try b.declare(&.{w.capability}, integer, &.{w.effect}, &.{region});
    const write_capability = try b.reference(b.parameter(written_body, 0));
    const info = try cleanup.exitInfo(b, unit);
    const start = try b.declare(&.{g.capability}, unit, &.{ w.effect, g.effect }, &.{region});
    const generated_body = try b.declare(&.{}, unit, &.{g.effect}, &.{region});
    const generated_cleanup = try b.declare(&.{info}, unit, &.{w.effect}, &.{region});
    try b.define(generated_body, try b.term(.{ .perform = .{
        .effect = g.effect,
        .capability = try b.reference(b.parameter(start, 0)),
        .payload = try b.constant(u64, 1),
    } }));
    try b.define(generated_cleanup, try b.term(.{ .perform = .{
        .effect = w.effect,
        .capability = write_capability,
        .payload = try b.constant(u64, 7),
    } }));
    const generated_body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = unit,
        .effects = &.{g.effect},
        .capture_bound = &.{g.capability},
        .regions = &.{region},
    } } });
    const cleanup_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{info},
        .result = unit,
        .effects = &.{w.effect},
        .capture_bound = &.{w.capability},
        .regions = &.{region},
    } } });
    try b.define(start, try b.term(.{ .protect = .{
        .body = try b.lambda(generated_body, generated_body_type),
        .cleanup = try b.lambda(generated_cleanup, cleanup_type),
    } }));
    const start_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{g.capability},
        .result = unit,
        .effects = &.{ w.effect, g.effect },
        .capture_bound = &.{w.capability},
        .regions = &.{region},
    } } });
    const body = try b.declare(&.{}, g.answer, &.{w.effect}, &.{region});
    try b.define(body, try b.term(.{ .handle = .{ .handler = g.handler, .body = try b.lambda(start, start_type) } }));
    const finalizer = try b.declare(&.{info}, unit, &.{w.effect}, &.{region});
    try b.define(finalizer, try b.term(.{ .perform = .{
        .effect = w.effect,
        .capability = write_capability,
        .payload = try b.constant(u64, 3),
    } }));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = g.answer,
        .effects = &.{w.effect},
        .capture_bound = &.{w.capability},
        .regions = &.{region},
    } } });
    const protected = try b.term(.{ .protect = .{ .body = try b.lambda(body, body_type), .cleanup = try b.lambda(finalizer, cleanup_type) } });
    const answer = try b.variable(g.answer);
    const done = try b.variable(unit);
    const yielded = try b.variable(g.yielded);
    const element = try b.variable(integer);
    const package = try b.variable(g.package);
    const result = try b.pure(try b.constant(u64, 42));
    const closed = try b.bind(try b.variable(unit), try generator.close(b, g, try b.reference(package)), result);
    const unpack = try b.term(.{ .unpack_product = .{ .value = try b.reference(yielded), .variables = &.{ element, package }, .body = closed } });
    const matched = try b.term(.{ .match_sum = .{ .value = try b.reference(answer), .cases = &.{ .{ .variable = done, .body = result }, .{ .variable = yielded, .body = unpack } } } });
    try b.define(written_body, try b.bind(answer, protected, matched));
    const written_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{w.capability},
        .result = integer,
        .effects = &.{w.effect},
        .regions = &.{region},
    } } });
    const cell = try b.variable(written.cell);
    const installed = try b.term(.{ .handle = .{
        .handler = written.handler,
        .body = try b.lambda(written_body, written_type),
        .state = &.{try b.reference(cell)},
    } });
    const empty = try b.primitive(written.sequence, .sequence, &.{}, 0);
    try b.define(inside, try b.bind(cell, try b.pure(try b.primitive(written.cell, .cell_new, &.{ try b.reference(b.parameter(inside, 0)), empty }, 0)), installed));
    const inside_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{region_type},
        .result = written.answer,
        .regions = &.{region},
    } } });
    try b.define(main, try b.term(.{ .with_region = .{ .region = region, .body = try b.lambda(inside, inside_type) } }));
    const handler = b.handlers.items[@intCast(written.handler)];
    const clause = handler.clauses[0].function;
    const prior = b.terms.items[@intCast(b.functions.items[@intCast(clause)].body.?)].bind;
    const log = try b.reference(b.parameter(clause, 0));
    const message = try b.reference(b.parameter(clause, 1));
    const token = try b.reference(b.parameter(clause, 2));
    const returned = try b.term(.{ .call = .{ .function = handler.return_function, .arguments = &.{ log, message } } });
    const marked = try b.bind(try b.variable(unit), try appendLog(b, log, try b.constant(u64, 99)), returned);
    const disposed = try b.bind(try b.variable(unit), try b.term(.{ .dispose = token }), marked);
    const condition = try b.primitive(try b.scalar(bool), .equal, &.{ message, try b.constant(u64, 3) }, 0);
    b.functions.items[@intCast(clause)].body = try b.bind(try b.variable(unit), prior.value, try b.term(.{ .conditional = .{ .condition = condition, .when_true = disposed, .when_false = prior.next } }));
    return b.module(main, unit);
}
