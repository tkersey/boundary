// Copyright (c) 2026 Boundary contributors. MIT license.
//! Authored Boolean choice interpretations. The runtime has no choice operation.
const source = @import("../source.zig");
const authoring = @import("../authoring.zig");
const p = @import("boundary_data").program;
const Error = source.Error;
pub const Family = struct { effect: p.Id, capability: p.Id };
pub const Interpretation = struct { handler: p.Id, answer: p.Id, resumption: p.Id };

pub fn family(builder: *source.Builder, identity: []const u8) Error!Family {
    var a = authoring.Builder.init(builder);
    const unit = a.scalar(void) catch |err| return authoring.sourceError(err);
    const boolean = a.scalar(bool) catch |err| return authoring.sourceError(err);
    const operation = a.local(identity, unit, boolean, .multi) catch |err| return authoring.sourceError(err);
    const capability = a.capability(operation) catch |err| return authoring.sourceError(err);
    return .{ .effect = operation.id, .capability = capability.id };
}

pub fn all(builder: *source.Builder, choice: Family, element: p.Id, captures: []const p.Id, residual: source.Row) Error!Interpretation {
    return interpret(builder, choice, element, captures, residual, &.{}, &.{}, true);
}
pub fn first(builder: *source.Builder, choice: Family, element: p.Id, captures: []const p.Id, residual: source.Row) Error!Interpretation {
    return interpret(builder, choice, element, captures, residual, &.{}, &.{}, false);
}
pub fn allScoped(builder: *source.Builder, choice: Family, element: p.Id, captures: []const p.Id, residual: source.Row, owned_regions: []const p.Id, borrowed_regions: []const p.Id) Error!Interpretation {
    return interpret(builder, choice, element, captures, residual, owned_regions, borrowed_regions, true);
}

fn interpret(builder: *source.Builder, choice: Family, element: p.Id, captures: []const p.Id, residual: source.Row, owned_regions: []const p.Id, borrowed_regions: []const p.Id, comptime every: bool) Error!Interpretation {
    const instance = try builder.specialization(Interpretation, "boundary.library.choice/v2", .{ choice, element, captures, residual, owned_regions, borrowed_regions, every });
    if (instance.cached) |value| return value;
    const result = forward(builder, choice, element, captures, residual, owned_regions, borrowed_regions, every) catch |err| return authoring.sourceError(err);
    return instance.finish(builder, result);
}

fn forward(builder: *source.Builder, choice: Family, element: p.Id, captures: []const p.Id, residual: source.Row, owned_regions: []const p.Id, borrowed_regions: []const p.Id, comptime every: bool) authoring.Error!Interpretation {
    var a = authoring.Builder.init(builder);
    const operation = try a.adoptEffect(choice.effect);
    const item = try a.adoptSchema(element);
    const answer = try a.sequenceSchema(item);
    const bounds = try builder.allocator().alloc(authoring.Schema, captures.len);
    for (captures, bounds) |id, *schema| schema.* = try a.adoptSchema(id);
    const effects = try builder.allocator().alloc(authoring.Effect, residual.effects.len);
    for (residual.effects, effects) |id, *effect| effect.* = try a.adoptEffect(id);
    const owned = try builder.allocator().alloc(authoring.Region, owned_regions.len);
    for (owned_regions, owned) |id, *region| region.* = try a.adoptRegion(id);
    const borrowed = try builder.allocator().alloc(authoring.Region, borrowed_regions.len);
    for (borrowed_regions, borrowed) |id, *region| region.* = try a.adoptRegion(id);
    const interpretation = try a.interpret(.{
        .operation = operation,
        .input = item,
        .answer = answer,
        .mode = .deep,
        .use = .multi,
        .residual = effects,
        .return_effects = &.{},
        .capture_bound = bounds,
        .owned_regions = owned,
        .borrowed_regions = borrowed,
    });
    var returns = try a.body(interpretation.returns);
    try a.define(interpretation.returns, try returns.finish(try returns.singletonSequence(try returns.parameter("value"))));
    var clause = try a.body(interpretation.clause);
    const token = try clause.parameter("resume");
    const left = try clause.resumeValue(token, try a.literal(bool, false));
    const value = if (every) blk: {
        const right = try clause.resumeValue(token, try a.literal(bool, true));
        break :blk try clause.concatSequences(left, right);
    } else left;
    try a.define(interpretation.clause, try clause.finish(value));
    return .{ .handler = interpretation.id, .answer = answer.id, .resumption = interpretation.resumption.id };
}
