// Copyright (c) 2026 Boundary contributors. MIT license.
//! Reader and local are authored handlers. Local supplies a new capability to
//! its inside computation and resumes the outside continuation with the old one.
const source = @import("../source.zig");
const p = @import("boundary_data_v2").program;
const Error = source.Error;
pub const Reader = struct { ask: p.Id, local: p.Id, ask_capability: p.Id, local_capability: p.Id, inside: p.Id, handler: p.Id, resumptions: []const p.Id };
pub const Captures = struct { continuation: []const p.Id, inside: []const p.Id = &.{} };

pub fn define(b: *source.Builder, identity: []const u8, environment: p.Id, result: p.Id, inside_result: p.Id, bounds: Captures, residual: source.Row, regions: []const p.Id) Error!Reader {
    const instance = try b.specialization(Reader, "boundary.library.reader/v2", .{ identity, environment, result, inside_result, bounds, residual, regions });
    if (instance.cached) |value| return value;
    const captures = bounds.continuation;
    const unit = try b.scalar(void);
    const ask = try b.effect(.{ .identity = try @import("std").fmt.allocPrint(b.allocator(), "{s}/ask", .{identity}), .payload = unit, .result = environment, .external = false });
    const ask_capability = try b.schema(.{ .internal = .{ .capability = ask } });
    const inside = try b.reserveSchema();
    const local = try b.effect(.{ .identity = try @import("std").fmt.allocPrint(b.allocator(), "{s}/local", .{identity}), .payload = environment, .result = inside_result, .bodies = &.{inside}, .external = false });
    const local_capability = try b.schema(.{ .internal = .{ .capability = local } });
    const effects = try residual.unionWith(b.allocator(), .{ .effects = &.{ ask, local } });
    const count: usize = if (result == inside_result) 1 else 2;
    const tokens = try b.allocator().alloc(p.Id, count * 2);
    for (tokens) |*token| token.* = try b.reserveSchema();
    const capture_bound = try b.allocator().alloc(p.Id, captures.len + 3 + tokens.len);
    @memcpy(capture_bound[0..captures.len], captures);
    capture_bound[captures.len] = ask_capability;
    capture_bound[captures.len + 1] = local_capability;
    capture_bound[captures.len + 2] = inside;
    @memcpy(capture_bound[captures.len + 3 ..], tokens);
    const inside_captures = try b.allocator().alloc(p.Id, bounds.inside.len + 1);
    @memcpy(inside_captures[0..bounds.inside.len], bounds.inside);
    inside_captures[bounds.inside.len] = inside;
    try b.defineSchema(inside, .{ .internal = .{ .computation = .{ .parameters = &.{ ask_capability, local_capability }, .result = inside_result, .effects = effects.effects, .capture_bound = inside_captures, .use = .linear, .regions = regions } } });
    var handlers: [2]p.Id = undefined;
    var clauses: [2]p.Id = undefined;
    for (0..count) |index| {
        const answer = if (index == 0) result else inside_result;
        const ask_token = tokens[index * 2];
        const local_token = tokens[index * 2 + 1];
        try b.defineSchema(ask_token, .{ .internal = .{ .resumption = .{ .effect = ask, .input = environment, .answer = answer, .effects = residual.effects, .capture_bound = capture_bound, .handled = &.{ ask, local }, .mode = .deep, .use = .linear } } });
        try b.defineSchema(local_token, .{ .internal = .{ .resumption = .{ .effect = local, .input = inside_result, .answer = answer, .effects = residual.effects, .capture_bound = capture_bound, .handled = &.{ ask, local }, .mode = .deep, .use = .linear } } });
        const returns = try b.declare(&.{ environment, answer }, answer, &.{}, regions);
        const ask_clause = try b.declare(&.{ environment, unit, ask_token }, answer, residual.effects, regions);
        const local_clause = try b.declare(&.{ environment, environment, inside, local_token }, answer, residual.effects, regions);
        clauses[index] = local_clause;
        handlers[index] = try b.handler(.{ .mode = .deep, .input = answer, .answer = answer, .return_function = returns, .state = &.{environment}, .effects = residual.effects, .clauses = &.{ .{ .effect = ask, .function = ask_clause, .resumption = ask_token }, .{ .effect = local, .function = local_clause, .resumption = local_token } } });
        try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 1))));
        try b.define(ask_clause, try b.term(.{ .resume_value = .{ .resumption = try b.reference(b.parameter(ask_clause, 2)), .argument = try b.reference(b.parameter(ask_clause, 0)) } }));
    }
    for (clauses[0..count]) |clause| {
        const value = try b.variable(inside_result);
        const inner = try b.term(.{ .handle = .{ .handler = handlers[count - 1], .body = try b.reference(b.parameter(clause, 2)), .state = &.{try b.reference(b.parameter(clause, 1))} } });
        const resumed = try b.term(.{ .resume_value = .{ .resumption = try b.reference(b.parameter(clause, 3)), .argument = try b.reference(value) } });
        try b.define(clause, try b.bind(value, inner, resumed));
    }
    return instance.finish(b, .{ .ask = ask, .local = local, .ask_capability = ask_capability, .local_capability = local_capability, .inside = inside, .handler = handlers[0], .resumptions = tokens });
}
