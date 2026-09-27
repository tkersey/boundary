// Copyright (c) 2026 Boundary contributors. MIT license.
//! Owned generators are ordinary deep handlers and recursive source data.
const source = @import("../source.zig");
const a = @import("../authoring.zig");
const p = @import("boundary_data").program;
const Error = source.Error;
pub const Generator = struct { input: p.Id, result: p.Id, effect: p.Id, capability: p.Id, element: p.Id, answer: p.Id, yielded: p.Id, package: p.Id, resumption: p.Id, handler: p.Id };
pub const Scope = struct {
    captures: []const p.Id = &.{},
    owned_regions: []const p.Id = &.{},
    borrowed_regions: []const p.Id = &.{},
    residual: source.Row = .{ .effects = &.{} },
};

/// Bidirectional owned exchange: supplied input advances to the next offered
/// output or completion. It never returns the preceding output again.
pub fn defineExchange(builder: *source.Builder, identity: []const u8, input: p.Id, element: p.Id, result: p.Id, captures: []const p.Id, owned_regions: []const p.Id, borrowed_regions: []const p.Id, residual: source.Row) Error!Generator {
    const instance = try builder.specialization(Generator, "boundary.library.exchange/v1", .{ identity, input, element, result, captures, owned_regions, borrowed_regions, residual });
    if (instance.cached) |value| return value;
    const value = authoredExchange(builder, identity, input, element, result, captures, owned_regions, borrowed_regions, residual) catch |err| return a.sourceError(err);
    return instance.finish(builder, value);
}

pub const Exchange = struct {
    input: *const a.Schema,
    element: *const a.Schema,
    result: *const a.Schema,
    effect: *const a.Operation,
    capability: *const a.Schema,
    answer: *const a.Schema,
    yielded: *const a.Schema,
    package: *const a.Schema,
    resumption: *const a.Schema,
    handler: *const a.Handler,
    fn sourceIds(self: @This(), c: *a.Context) a.Error!Generator {
        return .{ .input = try a.interop.schemaId(c, self.input), .result = try a.interop.schemaId(c, self.result), .effect = try a.interop.operationId(c, self.effect), .capability = try a.interop.schemaId(c, self.capability), .element = try a.interop.schemaId(c, self.element), .answer = try a.interop.schemaId(c, self.answer), .yielded = try a.interop.schemaId(c, self.yielded), .package = try a.interop.schemaId(c, self.package), .resumption = try a.interop.schemaId(c, self.resumption), .handler = try a.interop.handlerId(c, self.handler) };
    }
};
pub const Options = struct {
    captures: a.CaptureBounds,
    owned_regions: []const *const a.Region = &.{},
    borrowed_regions: []const *const a.Region = &.{},
    residual: []const *const a.Operation = &.{},
    parameters: []const a.Field = &.{},
    body_use: p.Use = .linear,
};

/// Declare a typed owned exchange. Reuse this definition for every endpoint
/// sharing its nominal operation and recursive answer contract.
pub fn create(c: *a.Context, identity: []const u8, input: *const a.Schema, element: *const a.Schema, result: *const a.Schema, options: Options) a.Error!Exchange {
    return makeExchange(c, identity, input, element, result, options.captures.continuation, options.owned_regions, options.borrowed_regions, options.residual, options.parameters, options.captures.body, options.body_use);
}

fn schemas(c: *a.Context, ids: []const p.Id) a.Error![]const *const a.Schema {
    const values = try a.interop.builder(c).allocator().alloc(*const a.Schema, ids.len);
    for (ids, values) |id, *value| value.* = try a.interop.schema(c, id);
    return values;
}
fn operations(c: *a.Context, ids: []const p.Id) a.Error![]const *const a.Operation {
    const values = try a.interop.builder(c).allocator().alloc(*const a.Operation, ids.len);
    for (ids, values) |id, *value| value.* = try a.interop.operation(c, id);
    return values;
}
fn regionHandles(c: *a.Context, ids: []const p.Id) a.Error![]const *const a.Region {
    const values = try a.interop.builder(c).allocator().alloc(*const a.Region, ids.len);
    for (ids, values) |id, *value| value.* = try a.interop.region(c, id);
    return values;
}
fn authoredExchange(b: *source.Builder, identity: []const u8, input: p.Id, element: p.Id, result: p.Id, captures: []const p.Id, owned_regions: []const p.Id, borrowed_regions: []const p.Id, residual: source.Row) a.Error!Generator {
    const c = try a.Context.init(b);
    const value = try makeExchange(c, identity, try a.interop.schema(c, input), try a.interop.schema(c, element), try a.interop.schema(c, result), try schemas(c, captures), try regionHandles(c, owned_regions), try regionHandles(c, borrowed_regions), try operations(c, residual.effects), &.{}, &.{}, .linear);
    return value.sourceIds(c);
}
fn makeExchange(c: *a.Context, identity: []const u8, input: *const a.Schema, element: *const a.Schema, result: *const a.Schema, captures: []const *const a.Schema, owned: []const *const a.Region, borrowed: []const *const a.Region, residual: []const *const a.Operation, parameters: []const a.Field, body_captures: []const *const a.Schema, body_use: p.Use) a.Error!Exchange {
    const effect = try c.local(identity, element, input, .linear);
    const capability = try c.capability(effect);
    const bound = try a.interop.builder(c).allocator().alloc(*const a.Schema, captures.len + 1);
    @memcpy(bound[0..captures.len], captures);
    bound[captures.len] = capability;
    const answer_declaration = try c.declareSchema(.alternatives);
    const answer = answer_declaration.schema();
    const handler = try c.handler(effect, result, answer, .{
        .mode = .deep,
        .use = .linear,
        .residual = residual,
        .return_effects = &.{},
        .clause_effects = &.{},
        .captures = bound,
        .body_captures = body_captures,
        .body_use = body_use,
        .owned_regions = owned,
        .borrowed_regions = borrowed,
        .obligations = true,
        .body_parameters = parameters,
    });
    const resumption = try c.resumptionSchemaFor(handler, effect);
    const package = try c.suspensionPackage(resumption);
    const yielded = try c.record(&.{ .{ .name = "value", .schema = element }, .{ .name = "future", .schema = package } });
    try c.defineAlternatives(answer_declaration, &.{ .{ .name = "done", .schema = result }, .{ .name = "yielded", .schema = yielded } });
    const returns_fn = try c.returnFunction(handler);
    const returns = try c.body(returns_fn);
    try c.define(returns_fn, try returns.ret(try returns.variant(answer, "done", try returns.parameter("result"))));
    const clause_fn = try c.clauseFunction(handler);
    const clause = try c.body(clause_fn);
    const suspended = try clause.package(try clause.parameter("resumption"));
    const offered = try clause.product(yielded, &.{ .{ .name = "value", .value = try clause.parameter("payload") }, .{ .name = "future", .value = suspended } });
    try c.define(clause_fn, try clause.ret(try clause.variant(answer, "yielded", offered)));
    return .{ .input = input, .result = result, .effect = effect, .capability = capability, .element = element, .answer = answer, .yielded = yielded, .package = package, .resumption = resumption, .handler = handler };
}

pub fn next(builder: *source.Builder, generator: Generator, package: p.Id) Error!p.Id {
    return builder.term(.{ .resume_value = .{ .resumption = try builder.primitive(generator.resumption, .unpack, &.{package}, 0), .argument = try builder.constant(void, {}) } });
}
pub fn close(builder: *source.Builder, generator: Generator, package: p.Id) Error!p.Id {
    return builder.term(.{ .dispose = try builder.primitive(generator.resumption, .unpack, &.{package}, 0) });
}

pub fn start(builder: *source.Builder, definition: Generator, body: p.Id, arguments: []const p.Id) Error!p.Id {
    return builder.term(.{ .handle = .{ .handler = definition.handler, .body = body, .arguments = arguments } });
}

pub fn offer(builder: *source.Builder, definition: Generator, capability: p.Id, outgoing: p.Id) Error!p.Id {
    return builder.term(.{ .perform = .{ .effect = definition.effect, .capability = capability, .payload = outgoing } });
}

/// Consume the old endpoint package and return its successor or completion.
pub fn exchange(builder: *source.Builder, definition: Generator, package: p.Id, input: p.Id) Error!p.Id {
    return builder.term(.{ .resume_value = .{ .resumption = try builder.primitive(definition.resumption, .unpack, &.{package}, 0), .argument = input } });
}

fn exchangeAllocation(allocator: @import("std").mem.Allocator) !void {
    var builder = source.Builder.init(allocator);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const boolean = try builder.scalar(bool);
    _ = try defineExchange(&builder, "allocation/exchange", integer, boolean, integer, &.{ integer, boolean }, &.{}, &.{}, .{ .effects = &.{} });
}
test "owned exchange construction releases partial allocation owners" {
    try @import("std").testing.checkAllAllocationFailures(@import("std").testing.allocator, exchangeAllocation, .{});
}

/// A derived sequential pipeline. Construction emits code only; start consumes
/// both running packages and its first input. Later exchange/close use generator.
pub const Composition = struct { generator: Generator, start: p.Id };
pub fn compose(builder: *source.Builder, identity: []const u8, left: Generator, right: Generator) Error!Composition {
    if (left.element != right.input or left.result != right.result) return error.TypeMismatch;
    if (left.resumption >= builder.schemas.items.len or right.resumption >= builder.schemas.items.len) return error.InvalidReference;
    const l = builder.schemas.items[@intCast(left.resumption)];
    const r = builder.schemas.items[@intCast(right.resumption)];
    if (l != .internal or r != .internal or l.internal != .resumption or r.internal != .resumption) return error.TypeMismatch;
    const cache = try builder.specialization(Composition, "boundary.library.exchange-compose/v1", .{ identity, left, right });
    if (cache.cached) |value| return value;
    const residual = try (source.Row{ .effects = l.internal.resumption.effects }).unionWith(builder.allocator(), .{ .effects = r.internal.resumption.effects });
    // These are declaration-region bounds. Dynamic owners remain distinct
    // packages; sharing a region descriptor never duplicates their custody.
    const regions = try unionRegions(builder, l.internal.resumption.owned_regions, r.internal.resumption.owned_regions);
    const borrowed = try unionRegions(builder, try borrowedRegions(builder, left), try borrowedRegions(builder, right));
    const composed = composeTyped(builder, identity, left, right, residual, regions, borrowed) catch |err| return a.sourceError(err);
    return cache.finish(builder, composed);
}
fn composeTyped(b: *source.Builder, identity: []const u8, left: Generator, right: Generator, residual: source.Row, owned_regions: []const p.Id, borrowed_regions: []const p.Id) a.Error!Composition {
    const c = try a.Context.init(b);
    const lp = try a.interop.schema(c, left.package);
    const rp = try a.interop.schema(c, right.package);
    const input = try a.interop.schema(c, left.input);
    const result = try a.interop.schema(c, left.result);
    const element = try a.interop.schema(c, right.element);
    const effects = try operations(c, residual.effects);
    const borrowed = try regionHandles(c, borrowed_regions);
    const parameters = &[_]a.Field{ .{ .name = "left", .schema = lp }, .{ .name = "right", .schema = rp }, .{ .name = "input", .schema = input } };
    const g = try makeExchange(c, identity, input, element, result, &.{ lp, rp, input, try a.interop.schema(c, left.element), element, result, try c.scalar(void) }, try regionHandles(c, owned_regions), borrowed, effects, parameters, &.{}, .linear);
    const loop_schema = try c.handledSchema(g.handler);
    const loop_fn = try c.functionFor("exchange pipeline", loop_schema);
    const loop = try c.body(loop_fn);
    const capability = try loop.parameter("capability");
    const right_package = try loop.parameter("right");
    const left_answer = try loop.resumeValue(try loop.unpack(try loop.parameter("left")), try loop.parameter("input"));
    const left_done = try loop.caseOf(left_answer, "0");
    _ = try left_done.body().dispose(try left_done.body().unpack(right_package));
    const left_yield = try loop.caseOf(left_answer, "1");
    const left_parts = try left_yield.body().destructure(left_yield.payload());
    const next_left = try left_parts.get("1");
    const right_answer = try left_yield.body().resumeValue(try left_yield.body().unpack(right_package), try left_parts.get("0"));
    const right_done = try left_yield.body().caseOf(right_answer, "0");
    _ = try right_done.body().dispose(try right_done.body().unpack(next_left));
    const right_yield = try left_yield.body().caseOf(right_answer, "1");
    const right_parts = try right_yield.body().destructure(right_yield.payload());
    const next_input = try right_yield.body().performLocal(g.effect, capability, try right_parts.get("0"));
    const continued = try right_yield.body().call(loop_fn, &.{ .{ .name = "capability", .value = capability }, .{ .name = "left", .value = next_left }, .{ .name = "right", .value = try right_parts.get("1") }, .{ .name = "input", .value = next_input } });
    const after_right = try left_yield.body().match(right_answer, &.{ try right_done.ret(right_done.payload()), try right_yield.ret(continued) });
    try c.define(loop_fn, try loop.ret(try loop.match(left_answer, &.{ try left_done.ret(left_done.payload()), try left_yield.ret(after_right) })));
    const entry_schema = try c.callable(parameters, g.answer, effects, .{ .use = .linear, .captures = &.{}, .regions = borrowed });
    const entry_fn = try c.functionFor("start exchange pipeline", entry_schema);
    const entry = try c.body(entry_fn);
    try c.define(entry_fn, try entry.ret(try entry.handleWithArguments(g.handler, try entry.lambda(loop_fn, loop_schema), &.{
        .{ .name = "left", .value = try entry.parameter("left") },   .{ .name = "right", .value = try entry.parameter("right") },
        .{ .name = "input", .value = try entry.parameter("input") },
    }, &.{})));
    return .{ .generator = try g.sourceIds(c), .start = try a.interop.functionId(c, entry_fn) };
}

fn borrowedRegions(b: *source.Builder, g: Generator) Error![]const p.Id {
    if (g.handler >= b.handlers.items.len) return error.InvalidReference;
    const function = b.handlers.items[@intCast(g.handler)].return_function;
    if (function >= b.functions.items.len) return error.InvalidReference;
    return b.functions.items[@intCast(function)].regions;
}
fn unionRegions(b: *source.Builder, left: []const p.Id, right: []const p.Id) Error![]const p.Id {
    const std = @import("std");
    var values: std.ArrayList(p.Id) = .empty;
    try values.appendSlice(b.allocator(), left);
    try values.appendSlice(b.allocator(), right);
    std.mem.sort(p.Id, values.items, {}, std.sort.asc(p.Id));
    var count: usize = 0;
    for (values.items) |id| if (count == 0 or values.items[count - 1] != id) {
        values.items[count] = id;
        count += 1;
    };
    values.items.len = count;
    return values.toOwnedSlice(b.allocator());
}

fn compositionAllocation(allocator: @import("std").mem.Allocator) !void {
    var b = source.Builder.init(allocator);
    defer b.deinit();
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const left = try defineExchange(&b, "allocation/left", integer, integer, integer, &.{integer}, &.{}, &.{}, .{ .effects = &.{} });
    const right = try defineExchange(&b, "allocation/right", integer, integer, integer, &.{integer}, &.{}, &.{}, .{ .effects = &.{} });
    const combined = try compose(&b, "allocation/combined", left, right);
    _ = try compose(&b, "allocation/three", combined.generator, right);
    const mismatch = try defineExchange(&b, "allocation/mismatch", boolean, integer, integer, &.{integer}, &.{}, &.{}, .{ .effects = &.{} });
    try @import("std").testing.expectError(error.TypeMismatch, compose(&b, "allocation/invalid", left, mismatch));
}
test "owned composition checks compatibility and releases partial construction" {
    const testing = @import("std").testing;
    try testing.checkAllAllocationFailures(testing.allocator, compositionAllocation, .{});
}
