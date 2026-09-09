// Copyright (c) 2026 Boundary contributors. MIT license.
//! Catch is an abortive interpretation that explicitly discharges the abandoned
//! continuation before returning its authored error value.
const source = @import("../source.zig");
const p = @import("boundary_data_v2").program;
pub const Raise = struct { effect: p.Id, capability: p.Id, answer: p.Id, resumption: p.Id, handler: p.Id };
pub const Family = struct { effect: p.Id, capability: p.Id, failure: p.Id };

pub fn family(b: *source.Builder, identity: []const u8, failure: p.Id) source.Error!Family {
    const effect = try b.effect(.{ .identity = identity, .payload = failure, .result = try b.scalar(void), .external = false });
    return .{ .effect = effect, .capability = try b.schema(.{ .internal = .{ .capability = effect } }), .failure = failure };
}

pub fn define(b: *source.Builder, identity: []const u8, failure: p.Id, result: p.Id, captures: []const p.Id, residual: source.Row, regions: []const p.Id) source.Error!Raise {
    return catching(b, try family(b, identity, failure), result, captures, residual, regions);
}
pub fn catching(b: *source.Builder, raised: Family, result: p.Id, captures: []const p.Id, residual: source.Row, regions: []const p.Id) source.Error!Raise {
    const instance = try b.specialization(Raise, "boundary.library.raise/v2", .{ raised, result, captures, residual, regions });
    if (instance.cached) |value| return value;
    const failure = raised.failure;
    const unit = try b.scalar(void);
    const answer = try b.schema(.{ .sum = &.{ failure, result } });
    const effect = raised.effect;
    const capability = raised.capability;
    const bound = try b.allocator().alloc(p.Id, captures.len + 1);
    @memcpy(bound[0..captures.len], captures);
    bound[captures.len] = capability;
    const token = try b.schema(.{ .internal = .{ .resumption = .{ .effect = effect, .input = unit, .answer = answer, .effects = residual.effects, .capture_bound = bound, .handled = &.{effect}, .mode = .deep, .use = .linear, .obligations = true } } });
    const returns = try b.declare(&.{result}, answer, &.{}, regions);
    try b.define(returns, try b.pure(try b.primitive(answer, .variant, &.{try b.reference(b.parameter(returns, 0))}, 1)));
    const clause = try b.declare(&.{ failure, token }, answer, residual.effects, regions);
    const disposed = try b.term(.{ .dispose = try b.reference(b.parameter(clause, 1)) });
    const caught = try b.pure(try b.primitive(answer, .variant, &.{try b.reference(b.parameter(clause, 0))}, 0));
    try b.define(clause, try b.bind(try b.variable(unit), disposed, caught));
    return instance.finish(b, .{ .effect = effect, .capability = capability, .answer = answer, .resumption = token, .handler = try b.handler(.{ .mode = .deep, .input = result, .answer = answer, .return_function = returns, .effects = residual.effects, .clauses = &.{.{ .effect = effect, .function = clause, .resumption = token }} }) });
}
