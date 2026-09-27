// Copyright (c) 2026 Boundary contributors. MIT license.
//! FIFO policy is ordinary recursive source code over an owned package queue.
const source = @import("../source.zig");
const a = @import("../authoring.zig");
const generator = @import("generator.zig");
const p = @import("boundary_data").program;
pub const Scheduler = struct { queue: p.Id, enqueue: p.Id, drain: p.Id };

pub fn fifo(b: *source.Builder, tasks: generator.Generator, residual: source.Row, regions: []const p.Id) source.Error!Scheduler {
    const instance = try b.specialization(Scheduler, "boundary.library.scheduler/fifo/v2", .{ tasks, residual, regions });
    if (instance.cached) |value| return value;
    const value = fifoTyped(b, tasks, residual, regions) catch |err| return a.sourceError(err);
    return instance.finish(b, value);
}
fn regionHandles(c: *a.Context, ids: []const p.Id) a.Error![]const *const a.Region {
    const values = try a.interop.builder(c).allocator().alloc(*const a.Region, ids.len);
    for (ids, values) |id, *value| value.* = try a.interop.region(c, id);
    return values;
}
fn fifoTyped(b: *source.Builder, tasks: generator.Generator, residual: source.Row, regions: []const p.Id) a.Error!Scheduler {
    const c = try a.Context.init(b);
    const unit = try c.scalar(void);
    const unit_id = try a.interop.schemaId(c, unit);
    if (tasks.input != unit_id or tasks.result != unit_id) return error.TypeMismatch;
    const queue = try c.sequence(try a.interop.schema(c, tasks.package));
    const answer = try a.interop.schema(c, tasks.answer);
    const bounds = try regionHandles(c, regions);
    const effects = try b.allocator().alloc(*const a.Operation, residual.effects.len);
    for (residual.effects, effects) |id, *effect| effect.* = try a.interop.operation(c, id);
    const enqueue_schema = try c.callable(&.{ .{ .name = "step", .schema = answer }, .{ .name = "queue", .schema = queue } }, queue, &.{}, .{ .use = .reusable, .captures = &.{}, .regions = bounds });
    const enqueue = try c.functionFor("enqueue", enqueue_schema);
    const push = try c.body(enqueue);
    const step = try push.parameter("step");
    const prior = try push.parameter("queue");
    const done = try push.caseOf(step, "0");
    const yielded = try push.caseOf(step, "1");
    const parts = try yielded.body().destructure(yielded.payload());
    const appended = try yielded.body().append(prior, try parts.get("1"));
    try c.define(enqueue, try push.ret(try push.match(step, &.{ try done.ret(prior), try yielded.ret(appended) })));
    const drain_schema = try c.callable(&.{.{ .name = "queue", .schema = queue }}, unit, effects, .{ .use = .reusable, .captures = &.{}, .regions = bounds });
    const drain = try c.functionFor("drain", drain_schema);
    const body = try c.body(drain);
    const popped = try body.pop(try body.parameter("queue"));
    const empty = try body.caseOf(popped, "empty");
    const ready = try body.caseOf(popped, "item");
    const item = try ready.body().destructure(ready.payload());
    const resumed = try ready.body().resumeValue(try ready.body().unpack(try item.get("head")), try ready.body().constant(void, {}));
    const next_queue = try ready.body().call(enqueue, &.{ .{ .name = "step", .value = resumed }, .{ .name = "queue", .value = try item.get("tail") } });
    const drained = try ready.body().call(drain, &.{.{ .name = "queue", .value = next_queue }});
    try c.define(drain, try body.ret(try body.match(popped, &.{ try empty.ret(try empty.body().constant(void, {})), try ready.ret(drained) })));
    return .{ .queue = try a.interop.schemaId(c, queue), .enqueue = try a.interop.functionId(c, enqueue), .drain = try a.interop.functionId(c, drain) };
}

pub const Join = struct { result: p.Id, cell: p.Id };
pub fn joinType(b: *source.Builder, result: p.Id, region: p.Id) source.Error!Join {
    const optional = try b.schema(.{ .sum = &.{ try b.scalar(void), result } });
    return .{ .result = optional, .cell = try b.schema(.{ .internal = .{ .cell = .{ .element = optional, .region = region } } }) };
}

pub fn awaiting(b: *source.Builder, tasks: generator.Generator, join: Join, result: p.Id, regions: []const p.Id) source.Error!p.Id {
    const instance = try b.specialization(p.Id, "boundary.library.scheduler/await/v2", .{ tasks, join, result, regions });
    if (instance.cached) |value| return value;
    const value = awaitTyped(b, tasks, join, result, regions) catch |err| return a.sourceError(err);
    return instance.finish(b, value);
}
fn awaitTyped(b: *source.Builder, tasks: generator.Generator, join: Join, result: p.Id, regions: []const p.Id) a.Error!p.Id {
    const c = try a.Context.init(b);
    if (tasks.element != try a.interop.schemaId(c, try c.scalar(void))) return error.TypeMismatch;
    const cell = try a.interop.schema(c, join.cell);
    const operation = try a.interop.operation(c, tasks.effect);
    const capability = try c.capability(operation);
    const schema = try c.callable(&.{ .{ .name = "cell", .schema = cell }, .{ .name = "capability", .schema = capability } }, try a.interop.schema(c, result), &.{operation}, .{ .use = .reusable, .captures = &.{}, .regions = try regionHandles(c, regions) });
    const function = try c.functionFor("await join", schema);
    const body = try c.body(function);
    const target = try body.parameter("cell");
    const cap = try body.parameter("capability");
    const value = try body.readCell(target);
    const pending = try body.caseOf(value, "0");
    const done = try body.caseOf(value, "1");
    _ = try pending.body().performLocal(operation, cap, try pending.body().constant(void, {}));
    const retry = try pending.body().call(function, &.{ .{ .name = "cell", .value = target }, .{ .name = "capability", .value = cap } });
    try c.define(function, try body.ret(try body.match(value, &.{ try pending.ret(retry), try done.ret(done.payload()) })));
    return a.interop.functionId(c, function);
}

pub fn complete(b: *source.Builder, join: Join, cell: p.Id, result: p.Id) source.Error!p.Id {
    return b.pure(try b.primitive(try b.scalar(void), .cell_set, &.{ cell, try b.primitive(join.result, .variant, &.{result}, 1) }, 0));
}

fn constructionAllocation(allocator: @import("std").mem.Allocator) !void {
    const testing = @import("std").testing;
    var b = source.Builder.init(allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const region = b.region();
    const tasks = try generator.defineScoped(&b, "scheduler/allocation", unit, &.{ unit, integer }, &.{}, &.{region}, .{ .effects = &.{} });
    const join = try joinType(&b, integer, region);
    const scheduler = try fifo(&b, tasks, .{ .effects = &.{} }, &.{region});
    const waiter = try awaiting(&b, tasks, join, integer, &.{region});
    const count = b.functions.items.len;
    for (0..64) |_| {
        try testing.expectEqual(scheduler.drain, (try fifo(&b, tasks, .{ .effects = &.{} }, &.{region})).drain);
        try testing.expectEqual(waiter, try awaiting(&b, tasks, join, integer, &.{region}));
    }
    try testing.expectEqual(count, b.functions.items.len);
}
test "typed scheduler construction shares definitions and releases allocation failures" {
    const testing = @import("std").testing;
    try testing.checkAllAllocationFailures(testing.allocator, constructionAllocation, .{});
}
test "FIFO requires unit input and unit completion" {
    const testing = @import("std").testing;
    var b = source.Builder.init(testing.allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const input = try generator.defineExchange(&b, "scheduler/input", integer, unit, unit, &.{}, &.{}, &.{}, .{ .effects = &.{} });
    const result = try generator.defineExchange(&b, "scheduler/result", unit, unit, integer, &.{}, &.{}, &.{}, .{ .effects = &.{} });
    try testing.expectError(error.TypeMismatch, fifo(&b, input, .{ .effects = &.{} }, &.{}));
    try testing.expectError(error.TypeMismatch, fifo(&b, result, .{ .effects = &.{} }, &.{}));
}
