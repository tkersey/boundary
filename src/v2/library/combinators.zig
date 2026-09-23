// Copyright (c) 2026 Boundary contributors. MIT license.
//! Staged higher-order combinators infer residual rows from the callable type.
const source = @import("../source.zig");
const author = @import("../author.zig");
const p = @import("boundary_data").program;

pub fn twice(builder: *source.Builder, computation: p.Id) source.Error!p.Id {
    if (computation >= builder.schemas.items.len) return error.InvalidSchema;
    const shape = builder.schemas.items[@intCast(computation)];
    if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
    const signature = shape.internal.computation;
    if (signature.parameters.len != 0 or signature.use != .reusable) return error.InvalidOwnership;
    const specialization = try builder.specialization(p.Id, "boundary.combinator.twice/v3", .{computation});
    if (specialization.cached) |function| return function;
    var a = try author.Session.init(builder);
    defer a.deinit();
    const legacy = a.legacy();
    const callable_schema = try legacy.schema(computation);
    const result = try legacy.schema(signature.result);
    const pair = try a.dynamicSchema(.{ .product = &.{ result.id, result.id } });
    const effects = try builder.allocator().alloc(author.Operation, signature.effects.len);
    for (effects, signature.effects) |*operation, id| operation.* = try legacy.operation(id);
    const function = try a.declare(&.{.{ .name = "callable", .schema = callable_schema }}, pair, effects);
    var body = try a.body(function);
    const callable = try body.parameter("callable");
    const first = try body.bind(try body.apply(callable, &.{}));
    const second = try body.bind(try body.apply(callable, &.{}));
    try body.finishFunction(try body.product(pair, &.{ first, second }));
    return specialization.finish(builder, function.id);
}
