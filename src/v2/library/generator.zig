// Copyright (c) 2026 Boundary contributors. MIT license.
//! Owned generators are ordinary deep handlers and recursive source data.
const source = @import("../source.zig");
const p = @import("boundary_data").program;
const Error = source.Error;
pub const Generator = struct { input: p.Id, result: p.Id, effect: p.Id, capability: p.Id, element: p.Id, answer: p.Id, yielded: p.Id, package: p.Id, resumption: p.Id, handler: p.Id };

pub fn define(builder: *source.Builder, identity: []const u8, element: p.Id, captures: []const p.Id, owned_regions: []const p.Id, residual: source.Row) Error!Generator {
    return defineScoped(builder, identity, element, captures, owned_regions, &.{}, residual);
}
pub fn defineScoped(builder: *source.Builder, identity: []const u8, element: p.Id, captures: []const p.Id, owned_regions: []const p.Id, borrowed_regions: []const p.Id, residual: source.Row) Error!Generator {
    const unit = try builder.scalar(void);
    return defineExchange(builder, identity, unit, element, unit, captures, owned_regions, borrowed_regions, residual);
}

/// Bidirectional owned exchange: supplied input advances to the next offered
/// output or completion. It never returns the preceding output again.
pub fn defineExchange(builder: *source.Builder, identity: []const u8, input: p.Id, element: p.Id, result: p.Id, captures: []const p.Id, owned_regions: []const p.Id, borrowed_regions: []const p.Id, residual: source.Row) Error!Generator {
    const instance = try builder.specialization(Generator, "boundary.library.exchange/v1", .{ identity, input, element, result, captures, owned_regions, borrowed_regions, residual });
    if (instance.cached) |value| return value;
    const unit = try builder.scalar(void);
    const effect = try builder.effect(.{ .identity = identity, .payload = element, .result = input, .external = false });
    const capability = try builder.schema(.{ .internal = .{ .capability = effect } });
    const capture_bound = try builder.allocator().alloc(p.Id, captures.len + 1);
    @memcpy(capture_bound[0..captures.len], captures);
    capture_bound[captures.len] = capability;
    const answer = try builder.reserveSchema();
    const resumption = try builder.schema(.{ .internal = .{ .resumption = .{ .effect = effect, .input = input, .answer = answer, .effects = residual.effects, .capture_bound = capture_bound, .handled = &.{effect}, .mode = .deep, .use = .linear, .owned_regions = owned_regions, .obligations = true } } });
    const package = try builder.schema(.{ .internal = .{ .suspension_package = resumption } });
    const yielded = try builder.schema(.{ .product = &.{ element, package } });
    try builder.defineSchema(answer, .{ .sum = &.{ result, yielded } });
    const returns = try builder.declare(&.{result}, answer, &.{}, borrowed_regions);
    try builder.define(returns, try builder.pure(try builder.primitive(answer, .variant, &.{if (result == unit) try builder.constant(void, {}) else try builder.reference(builder.parameter(returns, 0))}, 0)));
    const clause = try builder.declare(&.{ element, resumption }, answer, &.{}, borrowed_regions);
    const suspended = try builder.primitive(package, .package, &.{try builder.reference(builder.parameter(clause, 1))}, 0);
    const pair = try builder.primitive(yielded, .product, &.{ try builder.reference(builder.parameter(clause, 0)), suspended }, 0);
    try builder.define(clause, try builder.pure(try builder.primitive(answer, .variant, &.{pair}, 1)));
    return instance.finish(builder, .{ .input = input, .result = result, .effect = effect, .capability = capability, .element = element, .answer = answer, .yielded = yielded, .package = package, .resumption = resumption, .handler = try builder.handler(.{ .mode = .deep, .input = result, .answer = answer, .return_function = returns, .clauses = &.{.{ .effect = effect, .function = clause, .resumption = resumption }}, .effects = residual.effects }) });
}

pub fn next(builder: *source.Builder, generator: Generator, package: p.Id) Error!p.Id {
    return builder.term(.{ .resume_value = .{ .resumption = try builder.primitive(generator.resumption, .unpack, &.{package}, 0), .argument = try builder.constant(void, {}) } });
}
pub fn close(builder: *source.Builder, generator: Generator, package: p.Id) Error!p.Id {
    return builder.term(.{ .dispose = try builder.primitive(generator.resumption, .unpack, &.{package}, 0) });
}

/// Begin a fresh owned body with its first input. Body parameters are capability, input.
pub fn begin(builder: *source.Builder, definition: Generator, body: p.Id, input: p.Id) Error!p.Id {
    return builder.term(.{ .handle = .{ .handler = definition.handler, .body = body, .arguments = &.{input} } });
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
    const unit = try builder.scalar(void);
    const g = try defineExchange(builder, identity, left.input, right.element, left.result, &.{ left.package, right.package, left.input, left.element, right.element, left.result, unit }, regions, borrowed, residual);
    const active = try residual.unionWith(builder.allocator(), .{ .effects = &.{g.effect} });
    const loop = try builder.declare(&.{ g.capability, left.package, right.package, left.input }, g.result, active.effects, borrowed);
    const capability = try builder.reference(builder.parameter(loop, 0));
    const lp = try builder.reference(builder.parameter(loop, 1));
    const rp = try builder.reference(builder.parameter(loop, 2));
    const input = try builder.reference(builder.parameter(loop, 3));
    const la = try builder.variable(left.answer);
    const ra = try builder.variable(right.answer);
    const ly = try builder.variable(left.yielded);
    const ry = try builder.variable(right.yielded);
    const lv = try builder.variable(left.element);
    const rv = try builder.variable(right.element);
    const next_l = try builder.variable(left.package);
    const next_r = try builder.variable(right.package);
    const finished_l = try builder.variable(left.result);
    const finished_r = try builder.variable(right.result);
    const next_input = try builder.variable(g.input);
    const transfer = try builder.term(.{ .call = .{ .function = loop, .arguments = &.{ capability, try builder.reference(next_l), try builder.reference(next_r), try builder.reference(next_input) } } });
    const offered = try builder.bind(next_input, try builder.term(.{ .perform = .{ .effect = g.effect, .capability = capability, .payload = try builder.reference(rv) } }), transfer);
    const right_yield = try builder.term(.{ .unpack_product = .{ .value = try builder.reference(ry), .variables = &.{ rv, next_r }, .body = offered } });
    const right_done = try builder.bind(try builder.variable(unit), try close(builder, left, try builder.reference(next_l)), try builder.pure(try builder.reference(finished_r)));
    const after_right = try builder.term(.{ .match_sum = .{ .value = try builder.reference(ra), .cases = &.{
        .{ .variable = finished_r, .body = right_done }, .{ .variable = ry, .body = right_yield },
    } } });
    const advance_right = try builder.bind(ra, try exchange(builder, right, rp, try builder.reference(lv)), after_right);
    const left_yield = try builder.term(.{ .unpack_product = .{ .value = try builder.reference(ly), .variables = &.{ lv, next_l }, .body = advance_right } });
    const left_done = try builder.bind(try builder.variable(unit), try close(builder, right, rp), try builder.pure(try builder.reference(finished_l)));
    const after_left = try builder.term(.{ .match_sum = .{ .value = try builder.reference(la), .cases = &.{
        .{ .variable = finished_l, .body = left_done }, .{ .variable = ly, .body = left_yield },
    } } });
    try builder.define(loop, try builder.bind(la, try exchange(builder, left, lp, input), after_left));
    const body_type = try builder.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ g.capability, left.package, right.package, g.input }, .result = g.result, .effects = active.effects, .regions = borrowed } } });
    const start = try builder.declare(&.{ left.package, right.package, g.input }, g.answer, residual.effects, borrowed);
    try builder.define(start, try builder.term(.{ .handle = .{
        .handler = g.handler,
        .body = try builder.lambda(loop, body_type),
        .arguments = &.{ try builder.reference(builder.parameter(start, 0)), try builder.reference(builder.parameter(start, 1)), try builder.reference(builder.parameter(start, 2)) },
    } }));
    return cache.finish(builder, .{ .generator = g, .start = start });
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
