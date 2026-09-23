// Copyright (c) 2026 Boundary contributors. MIT license.
//! Checked bridge from the existing hyperfunction source library to staged bodies.
//! Raw IDs enter only here. Source admission still verifies captures and lifetimes.
const source = @import("../source.zig");
const a = @import("../authoring.zig");
const hyper = @import("hyper.zig");
const Id = source.Id;

pub const Types = struct {
    integer: Id,
    boolean: Id,
    task: Id,
    pair: hyper.Pair,
    read: Id,
    producer: hyper.demand.Family,
    consumer: hyper.demand.Family,
};

pub fn types(b: *source.Builder) source.Error!Types {
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

pub fn interpretation(b: *source.Builder, q: hyper.Query, need: hyper.demand.Family, t: Types) source.Error!hyper.demand.Interpretation {
    return hyper.demand.interpret(b, q, need, t.integer, .{
        .captures = &.{ t.boolean, t.integer, t.pair.peer_forward, t.pair.peer_backward },
        .residual = .{ .effects = &.{t.read} },
    });
}

pub fn request(body: *a.Body, need: hyper.demand.Family, capability: a.Value, next_state: a.Value, contribution: a.Schema) a.Error!a.Value {
    const cap = try a.Interop.rawValue(body, capability);
    const state = try a.Interop.rawValue(body, next_state);
    return a.Interop.term(body, try hyper.demand.request(body.author.raw, need, cap, state), contribution);
}

pub fn install(body: *a.Body, interpretation_handle: hyper.demand.Interpretation, peer: a.Value, work: a.Callable, result: a.Schema) a.Error!a.Value {
    const peer_id = try a.Interop.rawValue(body, peer);
    const work_id = try a.Interop.rawValue(body, work.value);
    return a.Interop.term(body, try hyper.demand.handle(body.author.raw, interpretation_handle, peer_id, work_id), result);
}

pub fn start(body: *a.Body, definition: hyper.Ana, state: a.Value, result: a.Schema) a.Error!a.Value {
    const state_id = try a.Interop.rawValue(body, state);
    return a.Interop.term(body, try hyper.start(body.author.raw, definition, state_id), result);
}

pub fn invoke(body: *a.Body, participant: a.Value, peer: a.Callable, result: a.Schema) a.Error!a.Value {
    const participant_id = try a.Interop.rawValue(body, participant);
    const peer_id = try a.Interop.rawValue(body, peer.value);
    return a.Interop.term(body, try hyper.invoke(body.author.raw, participant_id, peer_id), result);
}

pub fn force(body: *a.Body, delayed: a.Value, result: a.Schema) a.Error!a.Value {
    const id = try a.Interop.rawValue(body, delayed);
    return a.Interop.term(body, try hyper.force(body.author.raw, id), result);
}
