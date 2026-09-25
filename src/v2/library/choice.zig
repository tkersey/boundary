// Copyright (c) 2026 Boundary contributors. MIT license.
//! Authored Boolean choice interpretations. The runtime has no choice operation.
const a = @import("../authoring.zig");
const source = @import("../source.zig");
const p = @import("boundary_data").program;
const Error = source.Error;
pub const Family = struct { effect: p.Id, capability: p.Id };
pub const Interpretation = struct { handler: p.Id, answer: p.Id, resumption: p.Id };

pub fn family(builder: *source.Builder, identity: []const u8) Error!Family {
    return typedFamily(builder, identity) catch |err| return a.sourceError(err);
}
fn typedFamily(builder: *source.Builder, identity: []const u8) a.Error!Family {
    const c = try a.Context.init(builder);
    const effect = try c.local(identity, try c.scalar(void), try c.scalar(bool), .multi);
    return .{ .effect = try a.interop.operationId(c, effect), .capability = try a.interop.schemaId(c, try c.capability(effect)) };
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
    const value = typedInterpret(builder, choice, element, captures, residual, owned_regions, borrowed_regions, every) catch |err| return a.sourceError(err);
    return instance.finish(builder, value);
}

fn typedInterpret(builder: *source.Builder, choice: Family, element_id: p.Id, capture_ids: []const p.Id, residual: source.Row, owned_regions: []const p.Id, borrowed_regions: []const p.Id, comptime every: bool) a.Error!Interpretation {
    const c = try a.Context.init(builder);
    const operation = try a.interop.operation(c, choice.effect);
    const capability = try c.capability(operation);
    if (try a.interop.schemaId(c, capability) != choice.capability) return error.InvalidSource;
    const element = try a.interop.schema(c, element_id);
    const answer = try c.sequence(element);
    const captures = try builder.allocator().alloc(*const a.Schema, capture_ids.len);
    for (captures, capture_ids) |*out, id| out.* = try a.interop.schema(c, id);
    const effects = try builder.allocator().alloc(*const a.Operation, residual.effects.len);
    for (effects, residual.effects) |*out, id| out.* = try a.interop.operation(c, id);
    const owned = try builder.allocator().alloc(*const a.Region, owned_regions.len);
    for (owned, owned_regions) |*out, id| out.* = try a.interop.region(c, id);
    const borrowed = try builder.allocator().alloc(*const a.Region, borrowed_regions.len);
    for (borrowed, borrowed_regions) |*out, id| out.* = try a.interop.region(c, id);
    const h = try c.handler(operation, element, answer, .{ .mode = .deep, .use = .multi, .residual = effects, .captures = captures, .owned_regions = owned, .borrowed_regions = borrowed });
    const return_function = try c.returnFunction(h);
    const returns = try c.body(return_function);
    const singleton = try returns.sequenceValue(answer, &.{try returns.parameter("result")});
    try c.define(return_function, try returns.ret(singleton));
    const clause_function = try c.clauseFunction(h);
    const clause = try c.body(clause_function);
    const token = try clause.parameter("resumption");
    const left = try clause.resumeValue(token, try clause.constant(bool, false));
    const result = if (every) blk: {
        const right = try clause.resumeValue(token, try clause.constant(bool, true));
        break :blk try clause.concat(left, right);
    } else left;
    try c.define(clause_function, try clause.ret(result));
    return .{ .handler = try a.interop.handlerId(c, h), .answer = try a.interop.schemaId(c, answer), .resumption = try a.interop.schemaId(c, try a.interop.resumptionSchema(c, h)) };
}
