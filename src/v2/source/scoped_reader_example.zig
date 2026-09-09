// Copyright (c) 2026 Boundary contributors. MIT license.
//! Scoped forwarding transforms the inside computation as well as resuming the
//! outside continuation. Logging is an unrelated, typed residual effect.
const source = @import("../source.zig");
const reader_library = @import("../library/reader.zig");
const p = @import("boundary_data_v2").program;
const Error = source.Error;

pub fn build(b: *source.Builder) Error!source.ast.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const pair = try b.schema(.{ .product = &.{ integer, integer } });
    const log = try b.effect(.{ .identity = "example/reader-log", .payload = integer, .result = unit });
    var tokens: [4]p.Id = undefined;
    for (&tokens) |*token| token.* = try b.reserveSchema();
    const captures: []const p.Id = &.{ unit, integer, pair, tokens[0], tokens[1], tokens[2], tokens[3] };
    const reader = try reader_library.define(b, "example/scoped-reader", integer, pair, integer, .{ .continuation = captures }, .{ .effects = &.{log} }, &.{});
    const effects = &.{ log, reader.ask, reader.local };
    const bound = try b.allocator().alloc(p.Id, captures.len + reader.resumptions.len + 3);
    @memcpy(bound[0..captures.len], captures);
    @memcpy(bound[captures.len..][0..reader.resumptions.len], reader.resumptions);
    @memcpy(bound[bound.len - 3 ..], &[_]p.Id{ reader.ask_capability, reader.local_capability, reader.inside });
    var forwarding: [2]p.Id = undefined;
    var local_clauses: [2]p.Id = undefined;
    for ([_]p.Id{ pair, integer }, 0..) |answer, index| {
        const ask_token = tokens[index * 2];
        const local_token = tokens[index * 2 + 1];
        try b.defineSchema(ask_token, .{ .internal = .{ .resumption = .{ .effect = reader.ask, .input = integer, .answer = answer, .effects = effects, .capture_bound = bound, .handled = &.{ reader.ask, reader.local }, .mode = .deep, .use = .linear } } });
        try b.defineSchema(local_token, .{ .internal = .{ .resumption = .{ .effect = reader.local, .input = integer, .answer = answer, .effects = effects, .capture_bound = bound, .handled = &.{ reader.ask, reader.local }, .mode = .deep, .use = .linear } } });
        const returns = try b.declare(&.{ reader.ask_capability, reader.local_capability, answer }, answer, &.{}, &.{});
        const asks = try b.declare(&.{ reader.ask_capability, reader.local_capability, unit, ask_token }, answer, effects, &.{});
        const locals = try b.declare(&.{ reader.ask_capability, reader.local_capability, integer, reader.inside, local_token }, answer, effects, &.{});
        local_clauses[index] = locals;
        forwarding[index] = try b.handler(.{ .mode = .deep, .input = answer, .answer = answer, .return_function = returns, .state = &.{ reader.ask_capability, reader.local_capability }, .effects = effects, .clauses = &.{ .{ .effect = reader.ask, .function = asks, .resumption = ask_token }, .{ .effect = reader.local, .function = locals, .resumption = local_token } } });
        try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 2))));
        const logged = try b.variable(unit);
        const asked = try b.variable(integer);
        const request = try b.term(.{ .perform = .{ .effect = reader.ask, .capability = try b.reference(b.parameter(asks, 0)), .payload = try b.constant(void, {}) } });
        const resumed = try b.term(.{ .resume_value = .{ .resumption = try b.reference(b.parameter(asks, 3)), .argument = try b.reference(asked) } });
        try b.define(asks, try b.bind(logged, try b.term(.{ .perform = .{ .effect = log, .payload = try b.constant(u64, 1) } }), try b.bind(asked, request, resumed)));
    }
    for (local_clauses) |clause| {
        const wrapper = try b.declare(&.{ reader.ask_capability, reader.local_capability }, integer, effects, &.{});
        const wrapped = try b.term(.{ .handle = .{ .handler = forwarding[1], .body = try b.reference(b.parameter(clause, 3)), .state = &.{ try b.reference(b.parameter(wrapper, 0)), try b.reference(b.parameter(wrapper, 1)) } } });
        try b.define(wrapper, wrapped);
        const logged = try b.variable(unit);
        const inside = try b.variable(integer);
        const forwarded = try b.term(.{ .perform = .{ .effect = reader.local, .capability = try b.reference(b.parameter(clause, 1)), .payload = try b.reference(b.parameter(clause, 2)), .bodies = &.{try b.lambda(wrapper, reader.inside)} } });
        const resumed = try b.term(.{ .resume_value = .{ .resumption = try b.reference(b.parameter(clause, 4)), .argument = try b.reference(inside) } });
        try b.define(clause, try b.bind(logged, try b.term(.{ .perform = .{ .effect = log, .payload = try b.constant(u64, 2) } }), try b.bind(inside, forwarded, resumed)));
    }
    const main = try b.declare(&.{}, pair, &.{log}, &.{});
    const reader_body = try b.declare(&.{ reader.ask_capability, reader.local_capability }, pair, effects, &.{});
    const client = try b.declare(&.{ reader.ask_capability, reader.local_capability }, pair, effects, &.{});
    const inside = try b.declare(&.{ reader.ask_capability, reader.local_capability }, integer, effects, &.{});
    try b.define(inside, try b.term(.{ .perform = .{ .effect = reader.ask, .capability = try b.reference(b.parameter(inside, 0)), .payload = try b.constant(void, {}) } }));
    const local_result = try b.variable(integer);
    const outer_result = try b.variable(integer);
    const local = try b.term(.{ .perform = .{ .effect = reader.local, .capability = try b.reference(b.parameter(client, 1)), .payload = try b.constant(u64, 20), .bodies = &.{try b.lambda(inside, reader.inside)} } });
    const outer = try b.term(.{ .perform = .{ .effect = reader.ask, .capability = try b.reference(b.parameter(client, 0)), .payload = try b.constant(void, {}) } });
    try b.define(client, try b.bind(local_result, local, try b.bind(outer_result, outer, try b.pure(try b.primitive(pair, .product, &.{ try b.reference(local_result), try b.reference(outer_result) }, 0)))));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ reader.ask_capability, reader.local_capability }, .result = pair, .effects = effects } } });
    try b.define(reader_body, try b.term(.{ .handle = .{ .handler = forwarding[0], .body = try b.lambda(client, body_type), .state = &.{ try b.reference(b.parameter(reader_body, 0)), try b.reference(b.parameter(reader_body, 1)) } } }));
    try b.define(main, try b.term(.{ .handle = .{ .handler = reader.handler, .body = try b.lambda(reader_body, body_type), .state = &.{try b.constant(u64, 10)} } }));
    return b.module(main, unit);
}
