// Copyright (c) 2026 Boundary contributors. MIT license.
//! Staged higher-order combinators infer residual rows from the callable type.
const source = @import("../source.zig");
const authoring = @import("../authoring.zig");
const p = @import("boundary_data").program;

pub fn twice(builder: *source.Builder, computation: p.Id) source.Error!p.Id {
    if (computation >= builder.schemas.items.len) return error.InvalidSchema;
    const shape = builder.schemas.items[@intCast(computation)];
    if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
    const signature = shape.internal.computation;
    if (signature.parameters.len != 0 or signature.use != .reusable) return error.InvalidOwnership;
    const specialization = try builder.specialization(p.Id, "boundary.combinator.twice/v3", .{computation});
    if (specialization.cached) |function| return function;
    const function = twiceForward(builder, computation, signature) catch |err| return authoring.sourceError(err);
    return specialization.finish(builder, function);
}

fn twiceForward(builder: *source.Builder, computation: p.Id, signature: p.ComputationType) authoring.Error!p.Id {
    var a = authoring.Builder.init(builder);
    const callable_schema = try a.adoptSchema(computation);
    const result = try a.adoptSchema(signature.result);
    const pair = try a.record(&.{
        .{ .name = "first", .schema = result },
        .{ .name = "second", .schema = result },
    });
    const effects = try builder.allocator().alloc(authoring.Effect, signature.effects.len);
    for (signature.effects, effects) |id, *effect| effect.* = try a.adoptEffect(id);
    const regions = try builder.allocator().alloc(authoring.Region, signature.regions.len);
    for (signature.regions, regions) |id, *region| region.* = try a.adoptRegion(id);
    const function = try a.declareScoped("twice", &.{.{ .name = "callable", .schema = callable_schema }}, pair.schema, effects, regions);
    var body = try a.body(function);
    const callable = try body.asCallable(try body.parameter("callable"));
    const first = try body.apply(callable, &.{});
    const second = try body.apply(callable, &.{});
    const value = try body.product(pair, &.{
        .{ .name = "first", .value = first },
        .{ .name = "second", .value = second },
    });
    try a.define(function, try body.finish(value));
    return function.id;
}
