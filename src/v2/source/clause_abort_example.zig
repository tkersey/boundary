// Copyright (c) 2026 Boundary contributors. MIT license.
//! A clause fails while still owning the continuation of a protected body.
const source = @import("../source.zig");
const cleanup = @import("../library/cleanup.zig");

pub fn build(b: *source.Builder) source.Error!source.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const info = try cleanup.exitInfo(b, integer);
    const operation = try b.effect(.{ .identity = "example/abort-owned-continuation", .payload = unit, .result = unit, .external = false });
    const release = try b.effect(.{ .identity = "example/abandoned-release", .payload = info, .result = unit });
    const cap = try b.schema(.{ .internal = .{ .capability = operation } });
    const token = try b.schema(.{ .internal = .{ .resumption = .{ .effect = operation, .input = unit, .answer = integer, .effects = &.{release}, .capture_bound = &.{ unit, cap }, .handled = &.{operation}, .mode = .deep, .use = .linear, .obligations = true } } });
    const returns = try b.declare(&.{integer}, integer, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 0))));
    const clause = try b.declare(&.{ unit, token }, integer, &.{release}, &.{});
    try b.define(clause, try b.term(.{ .fail = try b.constant(u64, 9) }));
    const handler = try b.handler(.{ .mode = .deep, .input = integer, .answer = integer, .return_function = returns, .effects = &.{release}, .clauses = &.{.{ .effect = operation, .function = clause, .resumption = token }} });
    const main = try b.declare(&.{}, integer, &.{release}, &.{});
    const body = try b.declare(&.{cap}, integer, &.{ operation, release }, &.{});
    const inside = try b.declare(&.{}, integer, &.{operation}, &.{});
    const performed = try b.term(.{ .perform = .{ .effect = operation, .capability = try b.reference(b.parameter(body, 0)), .payload = try b.constant(void, {}) } });
    try b.define(inside, try b.bind(try b.variable(unit), performed, try b.pure(try b.constant(u64, 42))));
    const release_fn = try b.declare(&.{info}, unit, &.{release}, &.{});
    try b.define(release_fn, try b.term(.{ .perform = .{ .effect = release, .payload = try b.reference(b.parameter(release_fn, 0)) } }));
    const inside_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{}, .result = integer, .effects = &.{operation}, .capture_bound = &.{cap} } } });
    const cleanup_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{info}, .result = unit, .effects = &.{release} } } });
    try b.define(body, try b.term(.{ .protect = .{ .body = try b.lambda(inside, inside_type), .cleanup = try b.lambda(release_fn, cleanup_type) } }));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{cap}, .result = integer, .effects = &.{ operation, release } } } });
    try b.define(main, try b.term(.{ .handle = .{ .handler = handler, .body = try b.lambda(body, body_type) } }));
    return b.module(main, integer);
}
