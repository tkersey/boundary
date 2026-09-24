const std = @import("std");
const source = @import("source.zig");
const a = @import("authoring.zig");
const testing = std.testing;

pub fn branchWitness(raw: *source.Builder) !source.Module {
    const c = try a.Context.init(raw);
    const integer = try c.scalar(u64);
    const boolean = try c.scalar(bool);
    const unit = try c.scalar(void);
    const lookup = try c.external("authoring/lookup", integer, integer);
    const entry = try c.function("entry", &.{.{ .name = "choose", .schema = boolean }}, integer, &.{lookup});
    const body = try c.body(entry);
    const yes = try body.branch();
    const no = try body.branch();
    const chosen = try body.conditional(try body.parameter("choose"), try yes.ret(try yes.perform(lookup, try yes.constant(u64, 19))), try no.ret(try no.constant(u64, 42)));
    try c.define(entry, try body.ret(chosen));
    return c.module(entry, unit);
}

test "authoring external branch compiles through authoritative admission" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    var compiled = try source.lower(testing.allocator, try branchWitness(&raw));
    defer compiled.deinit();
    try testing.expect(compiled.program.functions.len > 0);
}

test "A01 authoring rejects colliding live builder handles" {
    var left = source.Builder.init(testing.allocator);
    defer left.deinit();
    var right = source.Builder.init(testing.allocator);
    defer right.deinit();
    const a1 = try a.Context.init(&left);
    const a2 = try a.Context.init(&right);
    const s1 = try a1.scalar(u64);
    _ = try a2.scalar(u64);
    try testing.expectError(error.ForeignHandle, a2.function("bad", &.{}, s1, &.{}));
    try testing.expectEqual(error.ForeignHandle, a2.diagnostic.code.?);
}

test "A02 authoring rejects sibling and escaped branch locals but joins succeed" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const integer = try c.scalar(u64);
    const entry = try c.function("entry", &.{}, integer, &.{});
    const body = try c.body(entry);
    const left = try body.branch();
    const right = try body.branch();
    const local = try left.constant(u64, 7);
    try testing.expectError(error.OutOfScope, right.ret(local));
    try testing.expectError(error.OutOfScope, body.ret(local));
    const inherited = try body.constant(u64, 11);
    const joined = try body.conditional(try body.constant(bool, true), try left.ret(local), try right.ret(inherited));
    try c.define(entry, try body.ret(joined));
    try testing.expectError(error.ClosedBody, body.constant(u64, 0));
    var compiled = try source.lower(testing.allocator, try c.module(entry, try c.scalar(void)));
    defer compiled.deinit();
}

test "A14 authoring runtime selected named fields reject mismatches" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const integer = try c.scalar(u64);
    const record = try c.record(&.{.{ .name = "count", .schema = integer }});
    const entry = try c.function("entry", &.{.{ .name = "input", .schema = record }}, integer, &.{});
    const body = try c.body(entry);
    const input = try body.parameter("input");
    try testing.expectError(error.UnknownName, body.field(input, "absent"));
    try c.define(entry, try body.ret(try body.field(input, "count")));
    var compiled = try source.lower(testing.allocator, try c.module(entry, try c.scalar(void)));
    defer compiled.deinit();
}

fn allocationWitness(allocator: std.mem.Allocator) !void {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    _ = try branchWitness(&raw);
}
test "A15 authoring constructors and snapshot tolerate allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationWitness, .{});
}

test "authoring derived responder preserves explicit residual allowance" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const integer = try c.scalar(u64);
    const lookup = try c.external("lookup", integer, integer);
    const question = try c.local("question", integer, integer, .linear);
    const responder = try c.function("responder", &.{.{ .name = "key", .schema = integer }}, integer, &.{lookup});
    const response = try c.body(responder);
    try c.define(responder, try response.ret(try response.perform(lookup, try response.parameter("key"))));
    const h = try c.responder(question, integer, responder, .{ .mode = .deep, .use = .linear, .residual = &.{lookup}, .captures = &.{} });
    const schema = try c.handledSchema(h);
    const work = try c.functionFor("work", schema);
    const body = try c.body(work);
    const result = try body.performLocal(question, try body.parameter("capability"), try body.constant(u64, 19));
    try c.define(work, try body.ret(result));
    const entry = try c.function("entry", &.{}, integer, &.{lookup});
    const main = try c.body(entry);
    try c.define(entry, try main.ret(try main.handleWith(h, try main.lambda(work, schema), &.{})));
    var compiled = try source.lower(testing.allocator, try c.module(entry, unit));
    defer compiled.deinit();
}

test "authoring nested callable captures parent named value" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const integer = try c.scalar(u64);
    const entry = try c.function("entry", &.{.{ .name = "x", .schema = integer }}, integer, &.{});
    const body = try c.body(entry);
    const x = try body.parameter("x");
    const schema = try c.callable(&.{}, integer, &.{}, .{ .use = .reusable, .captures = &.{integer} });
    const nested = try c.functionFor("nested", schema);
    const inner = try body.closureBody(nested);
    try c.define(nested, try inner.ret(x));
    const result = try body.apply(try body.lambda(nested, schema), &.{});
    try c.define(entry, try body.ret(result));
    var compiled = try source.lower(testing.allocator, try c.module(entry, try c.scalar(void)));
    defer compiled.deinit();
}
