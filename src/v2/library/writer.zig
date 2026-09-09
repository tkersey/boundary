// Copyright (c) 2026 Boundary contributors. MIT license.
//! Dynamic log accumulation through an explicit cell outside the body capture.
const source = @import("../source.zig");
const p = @import("boundary_data_v2").program;
pub const Writer = struct { effect: p.Id, capability: p.Id, answer: p.Id, cell: p.Id, sequence: p.Id, handler: p.Id, resumption: p.Id };
pub const Family = struct { effect: p.Id, capability: p.Id, message: p.Id };

pub fn family(b: *source.Builder, identity: []const u8, message: p.Id) source.Error!Family {
    const effect = try b.effect(.{ .identity = identity, .payload = message, .result = try b.scalar(void), .external = false });
    return .{ .effect = effect, .capability = try b.schema(.{ .internal = .{ .capability = effect } }), .message = message };
}

pub fn define(b: *source.Builder, identity: []const u8, message: p.Id, result: p.Id, region: p.Id, captures: []const p.Id, residual: source.Row) source.Error!Writer {
    return interpret(b, try family(b, identity, message), result, region, captures, residual);
}
pub fn interpret(b: *source.Builder, writer: Family, result: p.Id, region: p.Id, captures: []const p.Id, residual: source.Row) source.Error!Writer {
    const instance = try b.specialization(Writer, "boundary.library.writer/v2", .{ writer, result, region, captures, residual });
    if (instance.cached) |value| return value;
    const message = writer.message;
    const unit = try b.scalar(void);
    const sequence = try b.schema(.{ .seq = message });
    const cell = try b.schema(.{ .internal = .{ .cell = .{ .element = sequence, .region = region } } });
    const answer = try b.schema(.{ .product = &.{ result, sequence } });
    const effect = writer.effect;
    const capability = writer.capability;
    const bound = try b.allocator().alloc(p.Id, captures.len + 3);
    @memcpy(bound[0..captures.len], captures);
    @memcpy(bound[captures.len..], &[_]p.Id{ capability, cell, sequence });
    const token = try b.schema(.{ .internal = .{ .resumption = .{ .effect = effect, .input = unit, .answer = answer, .effects = residual.effects, .capture_bound = bound, .handled = &.{effect}, .mode = .deep, .use = .linear, .obligations = true } } });
    const returns = try b.declare(&.{ cell, result }, answer, &.{}, &.{region});
    const logs = try b.primitive(sequence, .cell_get, &.{try b.reference(b.parameter(returns, 0))}, 0);
    try b.define(returns, try b.pure(try b.primitive(answer, .product, &.{ try b.reference(b.parameter(returns, 1)), logs }, 0)));
    const clause = try b.declare(&.{ cell, message, token }, answer, residual.effects, &.{region});
    const target = try b.reference(b.parameter(clause, 0));
    const before = try b.primitive(sequence, .cell_get, &.{target}, 0);
    const after = try b.primitive(sequence, .sequence_append, &.{ before, try b.reference(b.parameter(clause, 1)) }, 0);
    const changed = try b.pure(try b.primitive(unit, .cell_set, &.{ target, after }, 0));
    const resumed = try b.term(.{ .resume_value = .{ .resumption = try b.reference(b.parameter(clause, 2)), .argument = try b.constant(void, {}) } });
    try b.define(clause, try b.bind(try b.variable(unit), changed, resumed));
    return instance.finish(b, .{ .effect = effect, .capability = capability, .answer = answer, .cell = cell, .sequence = sequence, .resumption = token, .handler = try b.handler(.{ .mode = .deep, .input = result, .answer = answer, .return_function = returns, .state = &.{cell}, .effects = residual.effects, .clauses = &.{.{ .effect = effect, .function = clause, .resumption = token }} }) });
}
