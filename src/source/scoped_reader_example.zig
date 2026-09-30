// Copyright (c) 2026 Boundary contributors. MIT license.
//! Scoped forwarding transforms the inside computation and resumes the outside.
const source = @import("../source.zig");
const a = @import("../authoring.zig");
const reader_library = @import("../library/reader.zig");
pub fn build(b: *source.Builder) source.Error!source.Module {
    return authored(b) catch |err| return a.sourceError(err);
}
fn authored(b: *source.Builder) a.Error!source.Module {
    const c = try a.Context.init(b);
    const unit = try c.scalar(void);
    const integer = try c.scalar(u64);
    const pair = try c.record(&.{ .{ .name = "local", .schema = integer }, .{ .name = "outer", .schema = integer } });
    const log = try c.external("example/reader-log", integer, unit);
    var declarations: [4]*const a.SchemaDeclaration = undefined;
    var tokens: [4]*const a.Schema = undefined;
    for (&declarations, &tokens) |*slot, *schema| {
        slot.* = try c.declareSchema(.resumption);
        schema.* = slot.*.schema();
    }
    const captures: []const *const a.Schema = &.{ unit, integer, pair, tokens[0], tokens[1], tokens[2], tokens[3] };
    const family = try reader_library.family(c, "example/scoped-reader", integer, integer, &.{}, &.{log}, &.{});
    const reader = try reader_library.interpret(c, family, pair, .{ .continuation = captures });
    const effects = &.{ log, family.ask(), family.local() };
    const bound = try b.allocator().alloc(*const a.Schema, captures.len + reader.resumptions.len + 3);
    @memcpy(bound[0..captures.len], captures);
    @memcpy(bound[captures.len..][0..reader.resumptions.len], reader.resumptions);
    @memcpy(bound[bound.len - 3 ..], &[_]*const a.Schema{ family.askCapability(), family.localCapability(), family.inside() });
    var forwarding: [2]*const a.Handler = undefined;
    for ([_]*const a.Schema{ pair, integer }, &forwarding, 0..) |answer, *handler, index| {
        handler.* = try c.handlerSet(&.{ .{ .name = "ask", .operation = family.ask() }, .{ .name = "local", .operation = family.local() } }, answer, answer, .{
            .mode = .deep,
            .use = .linear,
            .residual = effects,
            .return_effects = &.{},
            .captures = bound,
            .body_captures = if (index == 0) &.{} else &.{family.inside()},
            .state = &.{ .{ .name = "outer_ask", .schema = family.askCapability() }, .{ .name = "outer_local", .schema = family.localCapability() } },
            .resumption_slots = declarations[index * 2 ..][0..2],
        });
        const returns_fn = try c.returnFunction(handler.*);
        const returns = try c.body(returns_fn);
        try c.define(returns_fn, try returns.ret(try returns.parameter("result")));
        const asks_fn = try c.clauseFunctionFor(handler.*, family.ask());
        const asks = try c.body(asks_fn);
        _ = try asks.perform(log, try asks.constant(u64, 1));
        const answer_value = try asks.performLocal(family.ask(), try asks.parameter("outer_ask"), try asks.constant(void, {}));
        try c.define(asks_fn, try asks.ret(try asks.resumeValue(try asks.parameter("resumption"), answer_value)));
    }
    for (forwarding) |handler| {
        const clause_fn = try c.clauseFunctionFor(handler, family.local());
        const clause = try c.body(clause_fn);
        const wrapper_fn = try c.functionFor("forward scoped body", family.inside());
        const wrapper = try clause.closureBody(wrapper_fn);
        const wrapped = try wrapper.handleWith(forwarding[1], try clause.parameter("inside"), &.{
            .{ .name = "outer_ask", .value = try wrapper.parameter("ask") }, .{ .name = "outer_local", .value = try wrapper.parameter("local") },
        });
        try c.define(wrapper_fn, try wrapper.ret(wrapped));
        _ = try clause.perform(log, try clause.constant(u64, 2));
        const forwarded = try clause.performScoped(family.local(), try clause.parameter("outer_local"), try clause.parameter("payload"), &.{.{ .name = "inside", .value = try clause.lambda(wrapper_fn, family.inside()) }});
        try c.define(clause_fn, try clause.ret(try clause.resumeValue(try clause.parameter("resumption"), forwarded)));
    }
    const inside_fn = try c.functionFor("local read", family.inside());
    const inside = try c.body(inside_fn);
    try c.define(inside_fn, try inside.ret(try inside.performLocal(family.ask(), try inside.parameter("ask"), try inside.constant(void, {}))));
    const client_schema = try c.handledSchema(forwarding[0]);
    const client_fn = try c.functionFor("client", client_schema);
    const client = try c.body(client_fn);
    const local = try client.performScoped(family.local(), try client.parameter("local"), try client.constant(u64, 20), &.{.{ .name = "inside", .value = try client.lambda(inside_fn, family.inside()) }});
    const outer = try client.performLocal(family.ask(), try client.parameter("ask"), try client.constant(void, {}));
    try c.define(client_fn, try client.ret(try client.product(pair, &.{ .{ .name = "local", .value = local }, .{ .name = "outer", .value = outer } })));
    const reader_schema = try c.handledSchema(reader.handler);
    const reader_fn = try c.functionFor("reader body", reader_schema);
    const reader_body = try c.body(reader_fn);
    const interpreted = try reader_body.handleWith(forwarding[0], try reader_body.lambda(client_fn, client_schema), &.{
        .{ .name = "outer_ask", .value = try reader_body.parameter("ask") }, .{ .name = "outer_local", .value = try reader_body.parameter("local") },
    });
    try c.define(reader_fn, try reader_body.ret(interpreted));
    const main = try c.function("entry", &.{}, pair, &.{log});
    const entry = try c.body(main);
    try c.define(main, try entry.ret(try entry.handleWith(reader.handler, try entry.lambda(reader_fn, reader_schema), &.{.{ .name = "environment", .value = try entry.constant(u64, 10) }})));
    return c.module(main, unit);
}
