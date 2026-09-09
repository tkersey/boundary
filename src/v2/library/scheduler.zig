// Copyright (c) 2026 Boundary contributors. MIT license.
//! FIFO policy is ordinary recursive source code over an owned package queue.
const source = @import("../source.zig");
const generator = @import("generator.zig");
const p = @import("boundary_data_v2").program;
pub const Scheduler = struct { queue: p.Id, enqueue: p.Id, drain: p.Id };

pub fn fifo(b: *source.Builder, tasks: generator.Generator, residual: source.Row, regions: []const p.Id) source.Error!Scheduler {
    const instance = try b.specialization(Scheduler, "boundary.library.scheduler/fifo/v2", .{ tasks, residual, regions });
    if (instance.cached) |value| return value;
    const unit = try b.scalar(void);
    const queue = try b.schema(.{ .seq = tasks.package });
    const popped = try b.schema(.{ .product = &.{ tasks.package, queue } });
    const optional = try b.schema(.{ .sum = &.{ unit, popped } });
    const enqueue = try b.declare(&.{ tasks.answer, queue }, queue, &.{}, regions);
    const drain = try b.declare(&.{queue}, unit, residual.effects, regions);
    const done = try b.variable(unit);
    const yielded = try b.variable(tasks.yielded);
    const item = try b.variable(tasks.element);
    const package = try b.variable(tasks.package);
    const prior = try b.reference(b.parameter(enqueue, 1));
    const appended = try b.pure(try b.primitive(queue, .sequence_append, &.{ prior, try b.reference(package) }, 0));
    const unpack = try b.term(.{ .unpack_product = .{ .value = try b.reference(yielded), .variables = &.{ item, package }, .body = appended } });
    try b.define(enqueue, try b.term(.{ .match_sum = .{ .value = try b.reference(b.parameter(enqueue, 0)), .cases = &.{ .{ .variable = done, .body = try b.pure(prior) }, .{ .variable = yielded, .body = unpack } } } }));
    const empty = try b.variable(unit);
    const ready = try b.variable(popped);
    const current = try b.variable(tasks.package);
    const rest = try b.variable(queue);
    const step = try b.variable(tasks.answer);
    const next_queue = try b.variable(queue);
    const recurse = try b.term(.{ .call = .{ .function = drain, .arguments = &.{try b.reference(next_queue)} } });
    const push = try b.term(.{ .call = .{ .function = enqueue, .arguments = &.{ try b.reference(step), try b.reference(rest) } } });
    const advance = try b.bind(step, try generator.next(b, tasks, try b.reference(current)), try b.bind(next_queue, push, recurse));
    const selected = try b.term(.{ .unpack_product = .{ .value = try b.reference(ready), .variables = &.{ current, rest }, .body = advance } });
    const pop = try b.primitive(optional, .sequence_pop, &.{try b.reference(b.parameter(drain, 0))}, 0);
    try b.define(drain, try b.term(.{ .match_sum = .{ .value = pop, .cases = &.{ .{ .variable = empty, .body = try b.pure(try b.constant(void, {})) }, .{ .variable = ready, .body = selected } } } }));
    return instance.finish(b, .{ .queue = queue, .enqueue = enqueue, .drain = drain });
}

pub const Join = struct { result: p.Id, cell: p.Id };
pub fn joinType(b: *source.Builder, result: p.Id, region: p.Id) source.Error!Join {
    const optional = try b.schema(.{ .sum = &.{ try b.scalar(void), result } });
    return .{ .result = optional, .cell = try b.schema(.{ .internal = .{ .cell = .{ .element = optional, .region = region } } }) };
}

pub fn awaiting(b: *source.Builder, tasks: generator.Generator, join: Join, result: p.Id, regions: []const p.Id) source.Error!p.Id {
    const instance = try b.specialization(p.Id, "boundary.library.scheduler/await/v2", .{ tasks, join, result, regions });
    if (instance.cached) |value| return value;
    const unit = try b.scalar(void);
    if (tasks.element != unit) return error.TypeMismatch;
    const function = try b.declare(&.{ join.cell, tasks.capability }, result, &.{tasks.effect}, regions);
    const cell = try b.reference(b.parameter(function, 0));
    const capability = try b.reference(b.parameter(function, 1));
    const pending = try b.variable(unit);
    const completed = try b.variable(result);
    const yielded = try b.variable(unit);
    const retry = try b.term(.{ .call = .{ .function = function, .arguments = &.{ cell, capability } } });
    const wait = try b.bind(yielded, try b.term(.{ .perform = .{ .effect = tasks.effect, .capability = capability, .payload = try b.constant(void, {}) } }), retry);
    try b.define(function, try b.term(.{ .match_sum = .{ .value = try b.primitive(join.result, .cell_get, &.{cell}, 0), .cases = &.{ .{ .variable = pending, .body = wait }, .{ .variable = completed, .body = try b.pure(try b.reference(completed)) } } } }));
    return instance.finish(b, function);
}

pub fn complete(b: *source.Builder, join: Join, cell: p.Id, result: p.Id) source.Error!p.Id {
    return b.pure(try b.primitive(try b.scalar(void), .cell_set, &.{ cell, try b.primitive(join.result, .variant, &.{result}, 1) }, 0));
}
