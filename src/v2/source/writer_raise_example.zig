// Copyright (c) 2026 Boundary contributors. MIT license.
const source = @import("../source.zig");
const writer = @import("../library/writer.zig");
const raise = @import("../library/raise.zig");
const cleanup = @import("../library/cleanup.zig");
const p = @import("boundary_data_v2").program;
const Error = source.Error;

pub fn build(b: *source.Builder) Error!source.ast.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const outcome = try b.schema(.{ .sum = &.{ integer, integer } });
    const region = b.region();
    const region_type = try b.schema(.{ .internal = .{ .region = region } });
    const w = try writer.family(b, "example/writer", integer);
    const r = try raise.family(b, "example/raise", integer);
    const written = try writer.interpret(b, w, outcome, region, &.{ unit, integer, outcome, r.capability }, .{ .effects = &.{} });
    const caught = try raise.catching(b, r, integer, &.{ unit, integer, w.capability }, .{ .effects = &.{w.effect} }, &.{region});
    const main = try b.declare(&.{}, written.answer, &.{}, &.{});
    const inside = try b.declare(&.{region_type}, written.answer, &.{}, &.{region});
    const written_body = try b.declare(&.{w.capability}, outcome, &.{w.effect}, &.{region});
    const caught_body = try b.declare(&.{r.capability}, integer, &.{ w.effect, r.effect }, &.{region});
    const body = try b.declare(&.{}, integer, &.{ w.effect, r.effect }, &.{region});
    const finalizer = try b.declare(&.{try cleanup.exitInfo(b, unit)}, unit, &.{w.effect}, &.{region});
    const write_capability = try b.reference(b.parameter(written_body, 0));
    const raise_capability = try b.reference(b.parameter(caught_body, 0));
    const before = try b.variable(unit);
    const thrown = try b.variable(unit);
    const forbidden = try b.variable(unit);
    const log1 = try b.term(.{ .perform = .{ .effect = w.effect, .capability = write_capability, .payload = try b.constant(u64, 1) } });
    const throw = try b.term(.{ .perform = .{ .effect = r.effect, .capability = raise_capability, .payload = try b.constant(u64, 9) } });
    const log2 = try b.term(.{ .perform = .{ .effect = w.effect, .capability = write_capability, .payload = try b.constant(u64, 2) } });
    try b.define(body, try b.bind(before, log1, try b.bind(thrown, throw, try b.bind(forbidden, log2, try b.pure(try b.constant(u64, 42))))));
    try b.define(finalizer, try b.term(.{ .perform = .{ .effect = w.effect, .capability = write_capability, .payload = try b.constant(u64, 3) } }));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{}, .result = integer, .effects = &.{ w.effect, r.effect }, .capture_bound = &.{ w.capability, r.capability }, .regions = &.{region} } } });
    const finalizer_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{try cleanup.exitInfo(b, unit)}, .result = unit, .effects = &.{w.effect}, .capture_bound = &.{w.capability}, .regions = &.{region} } } });
    try b.define(caught_body, try b.term(.{ .protect = .{ .body = try b.lambda(body, body_type), .cleanup = try b.lambda(finalizer, finalizer_type) } }));
    const caught_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{r.capability}, .result = integer, .effects = &.{ w.effect, r.effect }, .capture_bound = &.{w.capability}, .regions = &.{region} } } });
    try b.define(written_body, try b.term(.{ .handle = .{ .handler = caught.handler, .body = try b.lambda(caught_body, caught_type) } }));
    const written_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{w.capability}, .result = outcome, .effects = &.{w.effect}, .regions = &.{region} } } });
    const cell = try b.variable(written.cell);
    const empty = try b.primitive(written.sequence, .sequence, &.{}, 0);
    const handled = try b.term(.{ .handle = .{ .handler = written.handler, .body = try b.lambda(written_body, written_type), .state = &.{try b.reference(cell)} } });
    try b.define(inside, try b.bind(cell, try b.pure(try b.primitive(written.cell, .cell_new, &.{ try b.reference(b.parameter(inside, 0)), empty }, 0)), handled));
    const inside_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{region_type}, .result = written.answer, .regions = &.{region} } } });
    try b.define(main, try b.term(.{ .with_region = .{ .region = region, .body = try b.lambda(inside, inside_type) } }));
    return b.module(main, unit);
}
