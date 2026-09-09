// Copyright (c) 2026 Boundary contributors. MIT license.
//! Search exposes alternatives as immutable templates. DFS and BFS differ only
//! in where ordinary authored code inserts those alternatives into its worklist.
const source = @import("../source.zig");
const p = @import("boundary_data_v2").program;
pub const Order = enum { depth_first, breadth_first };
pub const Search = struct { pick: p.Id, reject: p.Id, pick_capability: p.Id, reject_capability: p.Id, step: p.Id, resumption: p.Id, handler: p.Id, solutions: p.Id, explore: p.Id, queue: p.Id };

pub fn define(b: *source.Builder, identity: []const u8, element: p.Id, captures: []const p.Id, residual: source.Row, owned_regions: []const p.Id, borrowed_regions: []const p.Id, comptime order: Order) source.Error!Search {
    const instance = try b.specialization(Search, "boundary.library.search/v2", .{ identity, element, captures, residual, owned_regions, borrowed_regions, order });
    if (instance.cached) |value| return value;
    const unit = try b.scalar(void);
    const boolean = try b.scalar(bool);
    const pick = try b.effect(.{ .identity = try std.fmt.allocPrint(b.allocator(), "{s}/pick", .{identity}), .payload = unit, .result = boolean, .control_use = .multi, .external = false });
    const reject = try b.effect(.{ .identity = try std.fmt.allocPrint(b.allocator(), "{s}/reject", .{identity}), .payload = unit, .result = unit, .control_use = .multi, .external = false });
    const pick_capability = try b.schema(.{ .internal = .{ .capability = pick } });
    const reject_capability = try b.schema(.{ .internal = .{ .capability = reject } });
    const bounds = try b.allocator().alloc(p.Id, captures.len + 2);
    @memcpy(bounds[0..captures.len], captures);
    bounds[captures.len..][0..2].* = .{ pick_capability, reject_capability };
    const step = try b.reserveSchema();
    const resumption = try b.schema(.{ .internal = .{ .resumption = .{ .effect = pick, .input = boolean, .answer = step, .effects = residual.effects, .capture_bound = bounds, .handled = &.{ pick, reject }, .mode = .deep, .use = .multi, .owned_regions = owned_regions } } });
    const rejected = try b.schema(.{ .internal = .{ .resumption = .{ .effect = reject, .input = unit, .answer = step, .effects = residual.effects, .capture_bound = bounds, .handled = &.{ pick, reject }, .mode = .deep, .use = .multi, .owned_regions = owned_regions } } });
    try b.defineSchema(step, .{ .sum = &.{ element, resumption, unit } });
    const returns = try b.declare(&.{element}, step, &.{}, borrowed_regions);
    const pick_clause = try b.declare(&.{ unit, resumption }, step, &.{}, borrowed_regions);
    const reject_clause = try b.declare(&.{ unit, rejected }, step, &.{}, borrowed_regions);
    try b.define(returns, try b.pure(try b.primitive(step, .variant, &.{try b.reference(b.parameter(returns, 0))}, 0)));
    try b.define(pick_clause, try b.pure(try b.primitive(step, .variant, &.{try b.reference(b.parameter(pick_clause, 1))}, 1)));
    try b.define(reject_clause, try b.pure(try b.primitive(step, .variant, &.{try b.constant(void, {})}, 2)));
    const handler = try b.handler(.{ .mode = .deep, .input = element, .answer = step, .return_function = returns, .clauses = &.{ .{ .effect = pick, .function = pick_clause, .resumption = resumption }, .{ .effect = reject, .function = reject_clause, .resumption = rejected } }, .effects = residual.effects });

    const solutions = try b.schema(.{ .seq = element });
    const task = try b.schema(.{ .product = &.{ resumption, boolean } });
    const queue = try b.schema(.{ .seq = task });
    const popped = try b.schema(.{ .product = &.{ task, queue } });
    const optional = try b.schema(.{ .sum = &.{ unit, popped } });
    const explore = try b.declare(&.{ step, queue, solutions }, solutions, residual.effects, borrowed_regions);
    const next = try b.declare(&.{ queue, solutions }, solutions, residual.effects, borrowed_regions);
    const solution = try b.variable(element);
    const branch = try b.variable(resumption);
    const failure = try b.variable(unit);
    const prior = try b.reference(b.parameter(explore, 1));
    const found = try b.reference(b.parameter(explore, 2));
    const token = try b.reference(branch);
    const left = try b.primitive(task, .product, &.{ token, try b.constant(bool, false) }, 0);
    const right = try b.primitive(task, .product, &.{ token, try b.constant(bool, true) }, 0);
    const alternatives = try b.primitive(queue, .sequence, &.{ left, right }, 0);
    const queued = try b.primitive(queue, .sequence_concat, if (order == .depth_first) &.{ alternatives, prior } else &.{ prior, alternatives }, 0);
    try b.define(explore, try b.term(.{ .match_sum = .{ .value = try b.reference(b.parameter(explore, 0)), .cases = &.{
        .{ .variable = solution, .body = try b.term(.{ .call = .{ .function = next, .arguments = &.{ prior, try b.primitive(solutions, .sequence_append, &.{ found, try b.reference(solution) }, 0) } } }) },
        .{ .variable = branch, .body = try b.term(.{ .call = .{ .function = next, .arguments = &.{ queued, found } } }) },
        .{ .variable = failure, .body = try b.term(.{ .call = .{ .function = next, .arguments = &.{ prior, found } } }) },
    } } }));
    const empty = try b.variable(unit);
    const present = try b.variable(popped);
    const current = try b.variable(task);
    const rest = try b.variable(queue);
    const template = try b.variable(resumption);
    const argument = try b.variable(boolean);
    const advanced = try b.variable(step);
    const done = try b.reference(b.parameter(next, 1));
    const resumed = try b.term(.{ .resume_value = .{ .resumption = try b.reference(template), .argument = try b.reference(argument) } });
    const recurse = try b.term(.{ .call = .{ .function = explore, .arguments = &.{ try b.reference(advanced), try b.reference(rest), done } } });
    const selected = try b.term(.{ .unpack_product = .{ .value = try b.reference(current), .variables = &.{ template, argument }, .body = try b.bind(advanced, resumed, recurse) } });
    const unpack = try b.term(.{ .unpack_product = .{ .value = try b.reference(present), .variables = &.{ current, rest }, .body = selected } });
    try b.define(next, try b.term(.{ .match_sum = .{ .value = try b.primitive(optional, .sequence_pop, &.{try b.reference(b.parameter(next, 0))}, 0), .cases = &.{ .{ .variable = empty, .body = try b.pure(done) }, .{ .variable = present, .body = unpack } } } }));
    return instance.finish(b, .{ .pick = pick, .reject = reject, .pick_capability = pick_capability, .reject_capability = reject_capability, .step = step, .resumption = resumption, .handler = handler, .solutions = solutions, .explore = explore, .queue = queue });
}
const std = @import("std");

pub fn collect(b: *source.Builder, search: Search, step: p.Id) source.Error!p.Id {
    return b.term(.{ .call = .{ .function = search.explore, .arguments = &.{ step, try b.primitive(search.queue, .sequence, &.{}, 0), try b.primitive(search.solutions, .sequence, &.{}, 0) } } });
}
