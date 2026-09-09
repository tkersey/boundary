// Copyright (c) 2026 Boundary contributors. MIT license.
//! State policy is authored code; a cell is explicit handler-owned state.
const source = @import("../source.zig");
const p = @import("boundary_data_v2").program;
const Error = source.Error;
pub const Family = struct { get: p.Id, put: p.Id, get_capability: p.Id, put_capability: p.Id, element: p.Id };
pub const Answer = enum { value, with_state, optional };
pub const Interpretation = struct { handler: p.Id, answer: p.Id, cell: p.Id };

pub fn family(b: *source.Builder, identity: []const u8, element: p.Id) Error!Family {
    const unit = try b.scalar(void);
    const get = try b.effect(.{ .identity = try @import("std").fmt.allocPrint(b.allocator(), "{s}/get", .{identity}), .payload = unit, .result = element, .external = false });
    const put = try b.effect(.{ .identity = try @import("std").fmt.allocPrint(b.allocator(), "{s}/put", .{identity}), .payload = element, .result = unit, .external = false });
    return .{ .get = get, .put = put, .get_capability = try b.schema(.{ .internal = .{ .capability = get } }), .put_capability = try b.schema(.{ .internal = .{ .capability = put } }), .element = element };
}

pub fn interpret(b: *source.Builder, state: Family, result: p.Id, region: p.Id, captures: []const p.Id, residual: source.Row, disposition: Answer) Error!Interpretation {
    const instance = try b.specialization(Interpretation, "boundary.library.state/v2", .{ state, result, region, captures, residual, disposition });
    if (instance.cached) |value| return value;
    const unit = try b.scalar(void);
    const cell = try b.schema(.{ .internal = .{ .cell = .{ .element = state.element, .region = region } } });
    const answer = switch (disposition) {
        .value => result,
        .with_state => try b.schema(.{ .product = &.{ result, state.element } }),
        .optional => try b.schema(.{ .sum = &.{ unit, result } }),
    };
    const returns = try b.declare(&.{ cell, result }, answer, &.{}, &.{region});
    const returned = try b.reference(b.parameter(returns, 1));
    try b.define(returns, try b.pure(switch (disposition) {
        .value => returned,
        .with_state => try b.primitive(answer, .product, &.{ returned, try b.primitive(state.element, .cell_get, &.{try b.reference(b.parameter(returns, 0))}, 0) }, 0),
        .optional => try b.primitive(answer, .variant, &.{returned}, 1),
    }));
    var clauses: [2]p.Clause = undefined;
    for ([_]p.Id{ state.get, state.put }, 0..) |effect, index| {
        const input = if (index == 0) state.element else unit;
        const payload = if (index == 0) unit else state.element;
        const token = try b.schema(.{ .internal = .{ .resumption = .{ .effect = effect, .input = input, .answer = answer, .effects = residual.effects, .capture_bound = captures, .handled = &.{ state.get, state.put }, .mode = .deep, .use = .linear } } });
        const clause = try b.declare(&.{ cell, payload, token }, answer, residual.effects, &.{region});
        const state_cell = try b.reference(b.parameter(clause, 0));
        const resumed = try b.term(.{ .resume_value = .{ .resumption = try b.reference(b.parameter(clause, 2)), .argument = if (index == 0) try b.primitive(state.element, .cell_get, &.{state_cell}, 0) else try b.constant(void, {}) } });
        const body = if (index == 0) resumed else try b.bind(try b.variable(unit), try b.pure(try b.primitive(unit, .cell_set, &.{ state_cell, try b.reference(b.parameter(clause, 1)) }, 0)), resumed);
        try b.define(clause, body);
        clauses[index] = .{ .effect = effect, .function = clause, .resumption = token };
    }
    return instance.finish(b, .{ .handler = try b.handler(.{ .mode = .deep, .input = result, .answer = answer, .return_function = returns, .clauses = &clauses, .state = &.{cell}, .effects = residual.effects }), .answer = answer, .cell = cell });
}
