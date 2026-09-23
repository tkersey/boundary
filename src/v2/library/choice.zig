// Copyright (c) 2026 Boundary contributors. MIT license.
//! Authored Boolean choice interpretations. The runtime has no choice operation.
const source = @import("../source.zig");
const author = @import("../author.zig");
const p = @import("boundary_data").program;
const Error = source.Error;
pub const Family = struct { effect: p.Id, capability: p.Id };
pub const Interpretation = struct { handler: p.Id, answer: p.Id, resumption: p.Id };

pub fn family(builder: *source.Builder, identity: []const u8) Error!Family {
    var a = try author.Session.init(builder);
    defer a.deinit();
    const operation = try a.local(identity, try a.scalar(void), try a.scalar(bool), .multi);
    return .{ .effect = operation.id, .capability = operation.capability.?.id };
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
    var a = try author.Session.init(builder);
    defer a.deinit();
    const legacy = a.legacy();
    const operation = try legacy.operation(choice.effect);
    const input = try legacy.schema(element);
    const answer = try a.sequence(input);
    const allowed = try builder.allocator().alloc(author.Operation, residual.effects.len);
    for (allowed, residual.effects) |*item, id| item.* = try legacy.operation(id);
    const bound = try builder.allocator().alloc(author.Schema, captures.len);
    for (bound, captures) |*item, id| item.* = try legacy.schema(id);
    const owned = try builder.allocator().alloc(author.Region, owned_regions.len);
    for (owned, owned_regions) |*item, id| item.* = try legacy.region(id);
    const borrowed = try builder.allocator().alloc(author.Region, borrowed_regions.len);
    for (borrowed, borrowed_regions) |*item, id| item.* = try legacy.region(id);
    const h = try a.interpret(operation, .{
        .mode = .deep,
        .input = input,
        .answer = answer,
        .residual = allowed,
        .resumption_use = .multi,
        .capture_bound = bound,
        .owned_regions = owned,
        .borrowed_regions = borrowed,
    });
    var returns = try a.body(h.on_return);
    try returns.finishFunction(try returns.singleton(answer, try returns.parameter("body_result")));
    var clause = try a.body(h.on_operation);
    const token = try clause.parameter("resume");
    const left = try clause.bind(try clause.resumeValue(token, try clause.constant(bool, false)));
    if (every) {
        const right = try clause.bind(try clause.resumeValue(token, try clause.constant(bool, true)));
        try clause.finishFunction(try clause.concat(left, right));
    } else try clause.finishFunction(left);
    return instance.finish(builder, .{ .handler = h.id, .answer = answer.id, .resumption = h.resumption.id });
}
