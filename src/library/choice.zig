// Copyright (c) 2026 Boundary contributors. MIT license.
//! Boolean choice interpretations are ordinary authored handlers.
const std = @import("std");
const a = @import("../authoring.zig");
pub const Family = opaque {
    pub fn effect(self: *const Family) *const a.Operation {
        return familyData(self).effect;
    }
    pub fn capability(self: *const Family) *const a.Schema {
        return familyData(self).capability;
    }
};
const FamilyData = struct { effect: *const a.Operation, capability: *const a.Schema, interpretations: std.ArrayList(Cached) = .empty };
fn familyData(value: *const Family) *FamilyData {
    return @ptrCast(@alignCast(@constCast(value)));
}
pub const Interpretation = struct { handler: *const a.Handler, answer: *const a.Schema, resumption: *const a.Schema };
pub const Options = struct {
    captures: a.CaptureBounds,
    residual: []const *const a.Operation,
    owned_regions: []const *const a.Region = &.{},
    borrowed_regions: []const *const a.Region = &.{},
};
const Cached = struct { element: *const a.Schema, options: Options, every: bool, value: Interpretation };
pub fn family(c: *a.Context, identity: []const u8) a.Error!*const Family {
    const effect = try c.local(identity, try c.scalar(void), try c.scalar(bool), .multi);
    const result = try a.interop.builder(c).allocator().create(FamilyData);
    result.* = .{ .effect = effect, .capability = try c.capability(effect) };
    return @ptrCast(result);
}
pub fn all(c: *a.Context, choice: *const Family, element: *const a.Schema, options: Options) a.Error!Interpretation {
    return interpret(c, choice, element, options, true);
}
pub fn first(c: *a.Context, choice: *const Family, element: *const a.Schema, options: Options) a.Error!Interpretation {
    return interpret(c, choice, element, options, false);
}
fn sameOptions(x: Options, y: Options) bool {
    return std.mem.eql(*const a.Schema, x.captures.continuation, y.captures.continuation) and
        std.mem.eql(*const a.Schema, x.captures.body, y.captures.body) and
        std.mem.eql(*const a.Operation, x.residual, y.residual) and
        std.mem.eql(*const a.Region, x.owned_regions, y.owned_regions) and
        std.mem.eql(*const a.Region, x.borrowed_regions, y.borrowed_regions);
}
fn interpret(c: *a.Context, choice: *const Family, element: *const a.Schema, options: Options, comptime every: bool) a.Error!Interpretation {
    const f = familyData(choice);
    _ = try c.capability(f.effect);
    for (f.interpretations.items) |entry| if (entry.element == element and entry.every == every and sameOptions(entry.options, options)) return entry.value;
    const answer = try c.sequence(element);
    const h = try c.handler(f.effect, element, answer, .{
        .mode = .deep,
        .use = .multi,
        .residual = options.residual,
        .return_effects = &.{},
        .captures = options.captures.continuation,
        .body_captures = options.captures.body,
        .owned_regions = options.owned_regions,
        .borrowed_regions = options.borrowed_regions,
    });
    const returns_fn = try c.returnFunction(h);
    const returns = try c.body(returns_fn);
    try c.define(returns_fn, try returns.ret(try returns.sequenceValue(answer, &.{try returns.parameter("result")})));
    const clause_fn = try c.clauseFunction(h);
    const clause = try c.body(clause_fn);
    const token = try clause.parameter("resumption");
    const left = try clause.resumeValue(token, try clause.constant(bool, false));
    const result = if (every) blk: {
        const right = try clause.resumeValue(token, try clause.constant(bool, true));
        break :blk try clause.concat(left, right);
    } else left;
    try c.define(clause_fn, try clause.ret(result));
    const value: Interpretation = .{ .handler = h, .answer = answer, .resumption = try c.resumptionSchemaFor(h, f.effect) };
    const allocator = a.interop.builder(c).allocator();
    try f.interpretations.append(allocator, .{ .element = element, .every = every, .value = value, .options = .{
        .captures = .{ .continuation = try allocator.dupe(*const a.Schema, options.captures.continuation), .body = try allocator.dupe(*const a.Schema, options.captures.body) },
        .residual = try allocator.dupe(*const a.Operation, options.residual),
        .owned_regions = try allocator.dupe(*const a.Region, options.owned_regions),
        .borrowed_regions = try allocator.dupe(*const a.Region, options.borrowed_regions),
    } });
    return value;
}
