// Copyright (c) 2026 Boundary contributors. MIT license.
const source = @import("../source.zig");
const state = @import("../library/state.zig");
const choice = @import("../library/choice.zig");
const p = @import("boundary_data_v2").program;
const Error = source.Error;
pub fn local(b: *source.Builder) Error!source.ast.Module {
    return build(b, true);
}
pub fn shared(b: *source.Builder) Error!source.ast.Module {
    return build(b, false);
}

fn build(b: *source.Builder, comptime choice_outside: bool) Error!source.ast.Module {
    const unit = try b.scalar(void);
    const boolean = try b.scalar(bool);
    const integer = try b.scalar(u64);
    const sequence = try b.schema(.{ .seq = integer });
    const r = b.region();
    const region = try b.schema(.{ .internal = .{ .region = r } });
    const cell = try b.schema(.{ .internal = .{ .cell = .{ .element = integer, .region = r } } });
    const s = try state.family(b, "example/counter", integer);
    const c = try choice.family(b, "example/branch");
    const all = try choice.allScoped(b, c, integer, &.{ unit, boolean, integer, sequence, cell, s.get_capability, s.put_capability, c.capability }, .{ .effects = if (choice_outside) &.{} else &.{ s.get, s.put } }, if (choice_outside) &.{r} else &.{}, if (choice_outside) &.{} else &.{r});
    const interpretation = try state.interpret(b, s, if (choice_outside) integer else sequence, r, &.{ unit, boolean, integer, sequence, cell, s.get_capability, s.put_capability, c.capability, all.resumption }, .{ .effects = if (choice_outside) &.{c.effect} else &.{} }, .value);
    const main = try b.declare(&.{}, sequence, &.{}, &.{});
    const scope_body = try b.declare(&.{region}, if (choice_outside) integer else sequence, if (choice_outside) &.{c.effect} else &.{}, &.{r});
    const state_body = try b.declare(&.{ s.get_capability, s.put_capability }, if (choice_outside) integer else sequence, if (choice_outside) &.{ s.get, s.put, c.effect } else &.{ s.get, s.put }, &.{r});
    const choice_body = try b.declare(&.{c.capability}, integer, if (choice_outside) &.{c.effect} else &.{ s.get, s.put, c.effect }, if (choice_outside) &.{} else &.{r});
    const get_cap = try b.reference(b.parameter(state_body, 0));
    const put_cap = try b.reference(b.parameter(state_body, 1));
    const choose_cap = try b.reference(b.parameter(choice_body, 0));
    const chosen = try b.variable(boolean);
    const before = try b.variable(integer);
    const after = try b.variable(integer);
    const updated = try b.variable(unit);
    const inc = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ try b.reference(before), try b.constant(u64, 1) }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
    const get = try b.term(.{ .perform = .{ .effect = s.get, .capability = get_cap, .payload = try b.constant(void, {}) } });
    const put = try b.term(.{ .perform = .{ .effect = s.put, .capability = put_cap, .payload = try b.reference(after) } });
    const choose = try b.term(.{ .perform = .{ .effect = c.effect, .capability = choose_cap, .payload = try b.constant(void, {}) } });
    const common = try b.bind(chosen, choose, try b.bind(before, get, try b.bind(after, try b.pure(inc), try b.bind(updated, put, try b.pure(try b.reference(after))))));
    if (choice_outside) {
        try b.define(state_body, common);
        const private_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{region}, .result = integer, .effects = &.{c.effect}, .capture_bound = &.{c.capability}, .regions = &.{r} } } });
        try b.define(choice_body, try b.term(.{ .with_region = .{ .region = r, .body = try b.lambda(scope_body, private_type) } }));
    } else {
        try b.define(choice_body, common);
        const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{c.capability}, .result = integer, .effects = &.{ s.get, s.put, c.effect }, .capture_bound = &.{ s.get_capability, s.put_capability }, .regions = &.{r} } } });
        try b.define(state_body, try b.term(.{ .handle = .{ .handler = all.handler, .body = try b.lambda(choice_body, body_type) } }));
    }
    const state_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ s.get_capability, s.put_capability }, .result = if (choice_outside) integer else sequence, .effects = if (choice_outside) &.{ s.get, s.put, c.effect } else &.{ s.get, s.put }, .capture_bound = if (choice_outside) &.{c.capability} else &.{}, .regions = &.{r} } } });
    const allocated = try b.variable(cell);
    const handle_state = try b.term(.{ .handle = .{ .handler = interpretation.handler, .body = try b.lambda(state_body, state_type), .state = &.{try b.reference(allocated)} } });
    try b.define(scope_body, try b.bind(allocated, try b.pure(try b.primitive(cell, .cell_new, &.{ try b.reference(b.parameter(scope_body, 0)), try b.constant(u64, 0) }, 0)), handle_state));
    if (choice_outside) {
        const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{c.capability}, .result = integer, .effects = &.{c.effect} } } });
        try b.define(main, try b.term(.{ .handle = .{ .handler = all.handler, .body = try b.lambda(choice_body, body_type) } }));
    } else {
        const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{region}, .result = sequence, .regions = &.{r} } } });
        try b.define(main, try b.term(.{ .with_region = .{ .region = r, .body = try b.lambda(scope_body, body_type) } }));
    }
    return b.module(main, unit);
}
