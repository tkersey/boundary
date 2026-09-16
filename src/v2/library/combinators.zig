// Copyright (c) 2026 Boundary contributors. MIT license.
//! Staged higher-order combinators infer residual rows from the callable type.
const source = @import("../source.zig");
const p = @import("boundary_data_v2").program;

pub fn twice(builder: *source.Builder, computation: p.Id) source.Error!p.Id {
    if (computation >= builder.schemas.items.len) return error.InvalidSchema;
    const shape = builder.schemas.items[@intCast(computation)];
    if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
    const signature = shape.internal.computation;
    if (signature.parameters.len != 0 or signature.use != .reusable) return error.InvalidOwnership;
    const specialization = try builder.specialization(p.Id, "boundary.combinator.twice/v3", .{computation});
    if (specialization.cached) |function| return function;
    const pair = try builder.schema(.{ .product = &.{ signature.result, signature.result } });
    const function = try builder.declare(&.{computation}, pair, signature.effects, signature.regions);
    const callable = try builder.reference(builder.parameter(function, 0));
    const first = try builder.variable(signature.result);
    const second = try builder.variable(signature.result);
    const apply = try builder.term(.{ .apply = .{ .computation = callable, .arguments = &.{} } });
    try builder.define(function, try builder.bind(first, apply, try builder.bind(second, apply, try builder.pure(try builder.primitive(pair, .product, &.{ try builder.reference(first), try builder.reference(second) }, 0)))));
    return specialization.finish(builder, function);
}
