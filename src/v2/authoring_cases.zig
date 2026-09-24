//! Executable public-surface acceptance cases, also compiled by the authoring suite.
const std = @import("std");
const source = @import("source.zig");
const a = @import("authoring.zig");
const data = @import("boundary_data");
const p = data.program;
pub const Kind = enum {
    deep,
    shallow,
    transform_deep,
    transform_shallow,
    bypass,
    twice,
    cleanup,
    lazy,
    demanded,
    failure_before,
    failure_after,
    match,
    configuration,
    arithmetic,
    arithmetic_fail,
    dispose,
    region,
    reusable_body,
};

pub fn build(raw: *source.Builder, kind: Kind) !source.Module {
    return switch (kind) {
        .deep, .shallow, .transform_deep, .transform_shallow, .bypass, .dispose, .reusable_body => handlerCase(raw, kind),
        .twice => twiceCase(raw),
        .cleanup => cleanupCase(raw),
        .lazy, .demanded => delayedCase(raw, kind == .demanded),
        .failure_before, .failure_after => failureCase(raw, kind == .failure_after),
        .match => matchCase(raw),
        .configuration => configurationCase(raw),
        .region => regionCase(raw),
        .arithmetic, .arithmetic_fail => arithmeticCase(raw, kind == .arithmetic_fail),
    };
}
fn handlerCase(raw: *source.Builder, kind: Kind) !source.Module {
    const c = try a.Context.init(raw);
    const unit = try c.scalar(void);
    const integer = try c.scalar(u64);
    const transformed = kind == .transform_deep or kind == .transform_shallow;
    const answer = if (transformed) try c.record(&.{.{ .name = "answer", .schema = integer }}) else integer;
    const mode: p.Mode = if (kind == .shallow or kind == .transform_shallow) .shallow else .deep;
    const use: p.Use = if (kind == .bypass) .affine else .linear;
    const question = try c.local("case/question", unit, unit, use);
    const cap = try c.capability(question);
    const h = try c.handler(question, integer, answer, .{
        .mode = mode,
        .use = use,
        .residual = if (mode == .shallow) &.{question} else &.{},
        .captures = &.{ integer, cap, unit },
        .body_use = if (kind == .reusable_body) .reusable else .linear,
    });
    const returns_fn = try c.returnFunction(h);
    const returns = try c.body(returns_fn);
    const returned = try returns.constant(u64, 99);
    try c.define(returns_fn, try returns.ret(if (transformed)
        try returns.product(answer, &.{.{ .name = "answer", .value = returned }})
    else
        returned));
    const clause_fn = try c.clauseFunction(h);
    const clause = try c.body(clause_fn);
    if (kind == .dispose) _ = try clause.dispose(try clause.parameter("resumption"));
    const resumed = if (kind == .bypass or kind == .dispose) try clause.constant(u64, 17) else try clause.resumeValue(try clause.parameter("resumption"), try clause.constant(void, {}));
    const scalar = if (transformed and mode == .deep) try clause.field(resumed, "answer") else resumed;
    const plus = try clause.checkedAdd(scalar, try clause.constant(u64, 1), try clause.constant(void, {}));
    try c.define(clause_fn, try clause.ret(if (transformed)
        try clause.product(answer, &.{.{ .name = "answer", .value = plus }})
    else
        plus));
    const body_schema = try c.handledSchema(h);
    const work = try c.functionFor("work", body_schema);
    const body = try c.body(work);
    _ = try body.performLocal(question, try body.parameter("capability"), try body.constant(void, {}));
    try c.define(work, try body.ret(try body.constant(u64, 42)));
    const entry = try c.function("entry", &.{}, answer, if (mode == .shallow) &.{question} else &.{});
    const entry_body = try c.body(entry);
    const callable_value = try entry_body.lambda(work, body_schema);
    const first = try entry_body.handleWith(h, callable_value, &.{});
    const result = if (kind == .reusable_body) try entry_body.checkedAdd(first, try entry_body.handleWith(h, callable_value, &.{}), try entry_body.constant(void, {})) else first;
    try c.define(entry, try entry_body.ret(result));
    return c.module(entry, unit);
}
fn twiceCase(raw: *source.Builder) !source.Module {
    const c = try a.Context.init(raw);
    const integer = try c.scalar(u64);
    const unit = try c.scalar(void);
    const lookup = try c.external("case/lookup", integer, integer);
    const schema = try c.callable(&.{}, integer, &.{lookup}, .{ .use = .reusable, .captures = &.{} });
    const work = try c.functionFor("request", schema);
    const body = try c.body(work);
    try c.define(work, try body.ret(try body.perform(lookup, try body.constant(u64, 19))));
    const twice = try c.twice(schema);
    const pair = try c.record(&.{
        .{ .name = "first", .schema = integer },
        .{ .name = "second", .schema = integer },
    });
    const entry = try c.function("entry", &.{}, pair, &.{lookup});
    const entry_body = try c.body(entry);
    try c.define(entry, try entry_body.ret(try entry_body.call(twice, &.{
        .{
            .name = "callable",
            .value = try entry_body.lambda(work, schema),
        },
    })));
    return c.module(entry, unit);
}
fn cleanupCase(raw: *source.Builder) !source.Module {
    const c = try a.Context.init(raw);
    const integer = try c.scalar(u64);
    const unit = try c.scalar(void);
    const lookup = try c.external("case/lookup", integer, integer);
    const release = try c.external("case/release", unit, unit);
    const work_schema = try c.callable(&.{}, integer, &.{lookup}, .{ .use = .linear, .captures = &.{} });
    const work = try c.functionFor("protected work", work_schema);
    const body = try c.body(work);
    try c.define(work, try body.ret(try body.perform(lookup, try body.constant(u64, 19))));
    const cleanup_schema = try c.callable(&.{.{ .name = "exit", .schema = try c.cleanupInfo(unit) }}, unit, &.{release}, .{ .use = .linear, .captures = &.{} });
    const cleanup = try c.functionFor("local cleanup", cleanup_schema);
    const finalizer = try c.body(cleanup);
    try c.define(cleanup, try finalizer.ret(try finalizer.perform(release, try finalizer.constant(void, {}))));
    const entry = try c.function("entry", &.{}, integer, &.{ lookup, release });
    const entry_body = try c.body(entry);
    const result = try entry_body.protect(try entry_body.lambda(work, work_schema), try entry_body.lambda(cleanup, cleanup_schema), &.{});
    const after = try entry_body.checkedAdd(result, try entry_body.constant(u64, 1), try entry_body.constant(void, {}));
    try c.define(entry, try entry_body.ret(after));
    return c.module(entry, unit);
}
fn delayedCase(raw: *source.Builder, demanded: bool) !source.Module {
    const c = try a.Context.init(raw);
    const integer = try c.scalar(u64);
    const unit = try c.scalar(void);
    const delay = try c.callable(&.{}, integer, &.{}, .{ .use = .reusable, .captures = &.{} });
    const failure = try c.functionFor("delayed overflow", delay);
    const delayed = try c.body(failure);
    const result = try delayed.checkedAdd(try delayed.constant(u64, std.math.maxInt(u64)), try delayed.constant(u64, 1), try delayed.constant(void, {}));
    try c.define(failure, try delayed.ret(result));
    const entry = try c.function("entry", &.{}, integer, &.{});
    const body = try c.body(entry);
    const thunk = try body.lambda(failure, delay);
    try c.define(entry, try body.ret(if (demanded) try body.apply(thunk, &.{}) else try body.constant(u64, 42)));
    return c.module(entry, unit);
}
fn failureCase(raw: *source.Builder, after: bool) !source.Module {
    const c = try a.Context.init(raw);
    const integer = try c.scalar(u64);
    const unit = try c.scalar(void);
    const lookup = try c.external("case/lookup", integer, integer);
    const entry = try c.function("entry", &.{}, integer, &.{lookup});
    const body = try c.body(entry);
    if (after) _ = try body.perform(lookup, try body.constant(u64, 19));
    const failed = try body.checkedAdd(try body.constant(u64, std.math.maxInt(u64)), try body.constant(u64, 1), try body.constant(void, {}));
    if (!after) _ = try body.perform(lookup, try body.constant(u64, 19));
    try c.define(entry, try body.ret(failed));
    return c.module(entry, unit);
}
fn matchCase(raw: *source.Builder) !source.Module {
    const c = try a.Context.init(raw);
    const integer = try c.scalar(u64);
    const sum = try c.alternatives(&.{
        .{ .name = "left", .schema = integer },
        .{ .name = "right", .schema = integer },
    });
    const entry = try c.function("entry", &.{.{ .name = "choice", .schema = sum }}, integer, &.{});
    const body = try c.body(entry);
    const choice = try body.parameter("choice");
    const left = try body.caseOf(try body.parameter("choice"), "left");
    const right = try body.caseOf(try body.parameter("choice"), "right");
    const plus = try right.body().checkedAdd(right.payload(), try right.body().constant(u64, 1), try right.body().constant(void, {}));
    const result = try body.match(choice, &.{ try right.ret(plus), try left.ret(left.payload()) });
    try c.define(entry, try body.ret(result));
    return c.module(entry, try c.scalar(void));
}
fn regionCase(raw: *source.Builder) !source.Module {
    const c = try a.Context.init(raw);
    const integer = try c.scalar(u64);
    const region = try c.region();
    const schema = try c.regionBodySchema(region, &.{.{ .name = "value", .schema = integer }}, integer, &.{}, .{ .use = .linear, .captures = &.{} });
    const work = try c.functionFor("scoped region", schema);
    const inner = try c.body(work);
    try c.define(work, try inner.ret(try inner.parameter("value")));
    const entry = try c.function("entry", &.{}, integer, &.{});
    const body = try c.body(entry);
    const value = try body.withRegion(region, try body.lambda(work, schema), &.{.{ .name = "value", .value = try body.constant(u64, 42) }});
    try c.define(entry, try body.ret(value));
    return c.module(entry, try c.scalar(void));
}
fn arithmeticCase(raw: *source.Builder, fail: bool) !source.Module {
    const c = try a.Context.init(raw);
    const integer = try c.scalar(u64);
    const fields = [_]a.Field{
        .{ .name = "add", .schema = integer },       .{ .name = "subtract", .schema = integer },
        .{ .name = "multiply", .schema = integer },  .{ .name = "divide", .schema = integer },
        .{ .name = "remainder", .schema = integer },
    };
    const result_schema = if (fail) integer else try c.record(&fields);
    const entry = try c.function("entry", &.{}, result_schema, &.{});
    const body = try c.body(entry);
    const left = try body.constant(u64, 5);
    const right = try body.constant(u64, if (fail) 0 else 2);
    const failure = try body.constant(void, {});
    if (fail) {
        const result = try body.checked(.divide, left, right, .{ .overflow = failure, .division_by_zero = failure });
        try c.define(entry, try body.ret(result));
    } else {
        var values: [fields.len]a.Argument = undefined;
        for (std.enums.values(a.Arithmetic), fields, &values) |op, named, *value| value.* = .{
            .name = named.name,
            .value = try body.checked(op, left, right, .{ .overflow = failure, .division_by_zero = if (op == .divide or op == .remainder) failure else null }),
        };
        try c.define(entry, try body.ret(try body.product(result_schema, &values)));
    }
    return c.module(entry, try c.scalar(void));
}
const Configured = struct {
    value: u64,
    fn define(self: Configured, c: *a.Context, integer: *const a.Schema) !*const a.Function {
        const function = try c.function("configured", &.{}, integer, &.{});
        const body = try c.body(function);
        try c.define(function, try body.ret(try body.constant(u64, self.value)));
        return function;
    }
};
fn configurationCase(raw: *source.Builder) !source.Module {
    const c = try a.Context.init(raw);
    const integer = try c.scalar(u64);
    const pair = try c.record(&.{
        .{ .name = "first", .schema = integer },
        .{ .name = "second", .schema = integer },
    });
    const first = try (Configured{ .value = 7 }).define(c, integer);
    const second = try (Configured{ .value = 11 }).define(c, integer);
    const entry = try c.function("entry", &.{}, pair, &.{});
    const body = try c.body(entry);
    const result = try body.product(pair, &.{
        .{ .name = "first", .value = try body.call(first, &.{}) },
        .{ .name = "second", .value = try body.call(second, &.{}) },
    });
    try c.define(entry, try body.ret(result));
    return c.module(entry, try c.scalar(void));
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const kind = std.meta.stringToEnum(Kind, args.next() orelse return error.MissingKind) orelse
        return error.InvalidKind;
    const format = args.next() orelse "bpi3";
    var raw = source.Builder.init(init.gpa);
    defer raw.deinit();
    const module = try build(&raw, kind);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (std.mem.eql(u8, format, "json")) {
        try std.json.Stringify.value(module, .{ .emit_strings_as_arrays = true }, &output.interface);
    } else {
        var compiled = try source.lower(init.gpa, module);
        defer compiled.deinit();
        const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(compiled.program));
        defer init.gpa.free(bytes);
        _ = try compiled.encode(init.gpa, bytes);
        try output.interface.writeAll(bytes);
    }
    try output.interface.flush();
}
