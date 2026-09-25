// Copyright (c) 2026 Boundary contributors. MIT license.
//! Staged higher-order combinators infer residual rows from the callable type.
const authoring = @import("../authoring.zig");
const source = @import("../source.zig");
const p = @import("boundary_data").program;

pub fn twice(builder: *source.Builder, computation: p.Id) source.Error!p.Id {
    if (computation >= builder.schemas.items.len) return error.InvalidSchema;
    const shape = builder.schemas.items[@intCast(computation)];
    if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
    const signature = shape.internal.computation;
    if (signature.parameters.len != 0 or signature.use != .reusable) return error.InvalidOwnership;
    const specialization = try builder.specialization(p.Id, "boundary.combinator.twice/v3", .{computation});
    if (specialization.cached) |function| return function;
    const function = typedTwice(builder, computation) catch |err| return authoring.sourceError(err);
    return specialization.finish(builder, function);
}

fn typedTwice(builder: *source.Builder, computation: p.Id) authoring.Error!p.Id {
    const c = try authoring.Context.init(builder);
    const callable_schema = try authoring.interop.schema(c, computation);
    return authoring.interop.functionId(c, try c.twice(callable_schema));
}
