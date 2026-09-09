// Copyright (c) 2026 Boundary contributors. MIT license.
//! Owned generators are ordinary deep handlers and recursive source data.
const source = @import("../source.zig");
const p = @import("boundary_data_v2").program;
const Error = source.Error;
pub const Generator = struct { effect: p.Id, capability: p.Id, element: p.Id, answer: p.Id, yielded: p.Id, package: p.Id, resumption: p.Id, handler: p.Id };

pub fn define(builder: *source.Builder, identity: []const u8, element: p.Id, captures: []const p.Id, owned_regions: []const p.Id, residual: source.Row) Error!Generator {
    return defineScoped(builder, identity, element, captures, owned_regions, &.{}, residual);
}
pub fn defineScoped(builder: *source.Builder, identity: []const u8, element: p.Id, captures: []const p.Id, owned_regions: []const p.Id, borrowed_regions: []const p.Id, residual: source.Row) Error!Generator {
    const instance = try builder.specialization(Generator, "boundary.library.generator/v2", .{ identity, element, captures, owned_regions, borrowed_regions, residual });
    if (instance.cached) |value| return value;
    const unit = try builder.scalar(void);
    const effect = try builder.effect(.{ .identity = identity, .payload = element, .result = unit, .external = false });
    const capability = try builder.schema(.{ .internal = .{ .capability = effect } });
    const capture_bound = try builder.allocator().alloc(p.Id, captures.len + 1);
    @memcpy(capture_bound[0..captures.len], captures);
    capture_bound[captures.len] = capability;
    const answer = try builder.reserveSchema();
    const resumption = try builder.schema(.{ .internal = .{ .resumption = .{ .effect = effect, .input = unit, .answer = answer, .effects = residual.effects, .capture_bound = capture_bound, .handled = &.{effect}, .mode = .deep, .use = .linear, .owned_regions = owned_regions, .obligations = true } } });
    const package = try builder.schema(.{ .internal = .{ .suspension_package = resumption } });
    const yielded = try builder.schema(.{ .product = &.{ element, package } });
    try builder.defineSchema(answer, .{ .sum = &.{ unit, yielded } });
    const returns = try builder.declare(&.{unit}, answer, &.{}, borrowed_regions);
    try builder.define(returns, try builder.pure(try builder.primitive(answer, .variant, &.{try builder.constant(void, {})}, 0)));
    const clause = try builder.declare(&.{ element, resumption }, answer, &.{}, borrowed_regions);
    const suspended = try builder.primitive(package, .package, &.{try builder.reference(builder.parameter(clause, 1))}, 0);
    const pair = try builder.primitive(yielded, .product, &.{ try builder.reference(builder.parameter(clause, 0)), suspended }, 0);
    try builder.define(clause, try builder.pure(try builder.primitive(answer, .variant, &.{pair}, 1)));
    return instance.finish(builder, .{ .effect = effect, .capability = capability, .element = element, .answer = answer, .yielded = yielded, .package = package, .resumption = resumption, .handler = try builder.handler(.{ .mode = .deep, .input = unit, .answer = answer, .return_function = returns, .clauses = &.{.{ .effect = effect, .function = clause, .resumption = resumption }}, .effects = residual.effects }) });
}

pub fn next(builder: *source.Builder, generator: Generator, package: p.Id) Error!p.Id {
    return builder.term(.{ .resume_value = .{ .resumption = try builder.primitive(generator.resumption, .unpack, &.{package}, 0), .argument = try builder.constant(void, {}) } });
}
pub fn close(builder: *source.Builder, generator: Generator, package: p.Id) Error!p.Id {
    return builder.term(.{ .dispose = try builder.primitive(generator.resumption, .unpack, &.{package}, 0) });
}
