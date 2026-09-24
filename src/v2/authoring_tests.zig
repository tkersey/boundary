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
    const h = try c.responder(question, integer, responder, .{
        .mode = .deep,
        .use = .linear,
        .residual = &.{lookup},
        .captures = &.{},
    });
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

test "A06 A07 A10 A12 structured acceptance cases cross authoritative admission" {
    for (std.enums.values(@import("authoring_cases.zig").Kind)) |kind| {
        var raw = source.Builder.init(testing.allocator);
        defer raw.deinit();
        var compiled = try source.lower(testing.allocator, try @import("authoring_cases.zig").build(&raw, kind));
        defer compiled.deinit();
    }
}

fn oneShot(allocator: std.mem.Allocator, sequential: bool) !void {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const integer = try c.scalar(u64);
    const unit = try c.scalar(void);
    const once = try c.callable(&.{}, integer, &.{}, .{ .use = .linear, .captures = &.{} });
    const work = try c.functionFor("once", once);
    const work_body = try c.body(work);
    try c.define(work, try work_body.ret(try work_body.constant(u64, 7)));
    const entry = try c.function("entry", &.{}, integer, &.{});
    const body = try c.body(entry);
    const owned = try body.lambda(work, once);
    const result = if (sequential) blk: {
        _ = try body.apply(owned, &.{});
        break :blk try body.apply(owned, &.{});
    } else blk: {
        const left = try body.branch();
        const right = try body.branch();
        break :blk try body.conditional(try body.constant(bool, true), try left.ret(try left.apply(owned, &.{})), try right.ret(try right.apply(owned, &.{})));
    };
    try c.define(entry, try body.ret(result));
    var compiled = try c.compile(allocator, entry, unit);
    defer compiled.deinit();
}
test "A08 one shot alternatives succeed but sequential double consumption rejects" {
    try oneShot(testing.allocator, false);
    try testing.expectError(error.UnavailableSlot, oneShot(testing.allocator, true));
}

test "A09 nominal same-name operation rejects foreign capability" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const left = try c.local("same", unit, unit, .linear);
    const right = try c.local("same", unit, unit, .linear);
    const entry = try c.function("entry", &.{.{ .name = "cap", .schema = try c.capability(left) }}, unit, &.{ left, right });
    const body = try c.body(entry);
    const cap = try body.parameter("cap");
    const payload = try body.constant(void, {});
    try testing.expectError(error.SchemaMismatch, body.performLocal(right, cap, payload));
    try testing.expectEqual(error.SchemaMismatch, c.diagnostic.code.?);
    _ = try body.performLocal(left, cap, payload);
}

test "A09 A17 missing residual effect has an inspectable source relationship" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const op = try c.external("external", unit, unit);
    const entry = try c.function("limited entry", &.{}, unit, &.{});
    const body = try c.body(entry);
    try c.define(entry, try body.ret(try body.perform(op, try body.constant(void, {}))));
    try testing.expectError(error.InvalidEffect, c.compile(testing.allocator, entry, unit));
    try testing.expectEqual(error.InvalidEffect, c.diagnostic.code.?);
    try testing.expect(c.diagnostic.source != null);
    try testing.expect(std.mem.indexOf(u8, c.diagnostic.relationship, "residual") != null);
}

test "A08 A17 exclusive capture does not become reusable by declaring its bound" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const once = try c.callable(&.{}, unit, &.{}, .{ .use = .linear, .captures = &.{} });
    const reusable = try c.callable(&.{}, unit, &.{}, .{ .use = .reusable, .captures = &.{once} });
    const once_fn = try c.functionFor("once", once);
    const once_body = try c.body(once_fn);
    try c.define(once_fn, try once_body.ret(try once_body.constant(void, {})));
    const entry = try c.function("entry", &.{}, unit, &.{});
    const body = try c.body(entry);
    const owned = try body.lambda(once_fn, once);
    const closure = try c.functionFor("exclusive capture", reusable);
    const nested = try body.closureBody(closure);
    try c.define(closure, try nested.ret(try nested.apply(owned, &.{})));
    try c.define(entry, try body.ret(try body.apply(try body.lambda(closure, reusable), &.{})));
    try testing.expectError(error.InvalidOwnership, c.compile(testing.allocator, entry, unit));
    try testing.expectEqual(error.InvalidOwnership, c.diagnostic.code.?);
}

test "A11 explicit reuse adds calls without duplicating definitions" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const integer = try c.scalar(u64);
    const function = try c.function("shared", &.{}, integer, &.{});
    const definition = try c.body(function);
    try c.define(function, try definition.ret(try definition.constant(u64, 7)));
    const entry = try c.function("entry", &.{}, integer, &.{});
    const body = try c.body(entry);
    const count = raw.functions.items.len;
    var result = try body.constant(u64, 0);
    for (0..8) |_| result = try body.call(function, &.{});
    try testing.expectEqual(count, raw.functions.items.len);
    try c.define(entry, try body.ret(result));
    var compiled = try c.compile(testing.allocator, entry, try c.scalar(void));
    defer compiled.deinit();
}

fn handlerAllocation(allocator: std.mem.Allocator) !void {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    _ = try @import("authoring_cases.zig").build(&raw, .transform_deep);
}
test "A15 handler construction and finalization allocation failures" {
    try testing.checkAllAllocationFailures(testing.allocator, handlerAllocation, .{});
}

fn labelBytes(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const integer = try c.scalar(u64);
    const entry = try c.function(name, &.{}, integer, &.{});
    const body = try c.body(entry);
    try c.define(entry, try body.ret(try body.constant(u64, 42)));
    var compiled = try c.compile(allocator, entry, try c.scalar(void));
    defer compiled.deinit();
    const bytes = try allocator.alloc(u8, try @import("boundary_data").program_image.encodedLength(compiled.program));
    errdefer allocator.free(bytes);
    _ = try compiled.encode(allocator, bytes);
    return bytes;
}
test "A17 source labels do not change executable bytes" {
    const left = try labelBytes(testing.allocator, "original");
    defer testing.allocator.free(left);
    const right = try labelBytes(testing.allocator, "renamed diagnostic label");
    defer testing.allocator.free(right);
    try testing.expectEqualSlices(u8, left, right);
}
fn diagnosticAllocation(allocator: std.mem.Allocator) !void {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const integer = try c.scalar(u64);
    const boolean = try c.scalar(bool);
    const entry = try c.function("named argument", &.{.{ .name = "input", .schema = integer }}, integer, &.{});
    const caller = try c.function("caller", &.{}, integer, &.{});
    const body = try c.body(caller);
    const wrong = try body.constant(bool, false);
    _ = boolean;
    _ = body.call(entry, &.{.{ .name = "input", .value = wrong }}) catch |err| {
        if (err != error.SchemaMismatch) return err;
        const rendered = try c.diagnostic.renderAlloc(allocator);
        defer allocator.free(rendered);
        try testing.expect(std.mem.indexOf(u8, rendered, "expected u64") != null);
        return;
    };
    return error.TestExpectedError;
}
test "A15 A17 diagnostic rendering fails cleanly under allocation pressure" {
    try testing.checkAllAllocationFailures(testing.allocator, diagnosticAllocation, .{});
}

test "structured scoped operations expose named body and state clauses" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const integer = try c.scalar(u64);
    const thunk = try c.callable(&.{}, integer, &.{}, .{ .use = .linear, .captures = &.{} });
    const op = try c.scoped("scoped", unit, integer, .linear, &.{.{ .name = "work", .schema = thunk }});
    const h = try c.handler(op, integer, integer, .{
        .mode = .deep,
        .use = .linear,
        .residual = &.{},
        .captures = &.{integer},
        .state = &.{.{ .name = "offset", .schema = integer }},
    });
    const returns_fn = try c.returnFunction(h);
    const returns = try c.body(returns_fn);
    try c.define(returns_fn, try returns.ret(try returns.parameter("result")));
    const clause_fn = try c.clauseFunction(h);
    const clause = try c.body(clause_fn);
    const answer = try clause.apply(try clause.parameter("work"), &.{});
    const plus = try clause.checkedAdd(answer, try clause.parameter("offset"), try clause.constant(void, {}));
    try c.define(clause_fn, try clause.ret(try clause.resumeValue(try clause.parameter("resumption"), plus)));
    const nested_fn = try c.functionFor("scoped work", thunk);
    const nested = try c.body(nested_fn);
    try c.define(nested_fn, try nested.ret(try nested.constant(u64, 41)));
    const schema = try c.handledSchema(h);
    const work_fn = try c.functionFor("handled", schema);
    const work = try c.body(work_fn);
    const value = try work.performScoped(op, try work.parameter("capability"), try work.constant(void, {}), &.{.{ .name = "work", .value = try work.lambda(nested_fn, thunk) }});
    try c.define(work_fn, try work.ret(value));
    const entry = try c.function("entry", &.{}, integer, &.{});
    const body = try c.body(entry);
    const result = try body.handleWith(h, try body.lambda(work_fn, schema), &.{.{ .name = "offset", .value = try body.constant(u64, 1) }});
    try c.define(entry, try body.ret(result));
    var compiled = try c.compile(testing.allocator, entry, unit);
    defer compiled.deinit();
}

test "A02 parent finalization and abandonment close descendant authoring" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const f = try c.function("entry", &.{}, unit, &.{});
    const body = try c.body(f);
    const abandoned = try body.branch();
    const grandchild = try abandoned.branch();
    abandoned.abandon();
    try testing.expectError(error.ClosedBody, grandchild.constant(void, {}));
    const pending = try body.branch();
    try c.define(f, try body.ret(try body.constant(void, {})));
    try testing.expectError(error.ClosedBody, pending.constant(void, {}));
    var compiled = try c.compile(testing.allocator, f, unit);
    defer compiled.deinit();
}

test "A14 named-layout and branch result mismatches reject before source admission" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const integer = try c.scalar(u64);
    const first = try c.record(&.{.{ .name = "first", .schema = integer }});
    const second = try c.record(&.{.{ .name = "second", .schema = integer }});
    const f = try c.function("entry", &.{}, first, &.{});
    const body = try c.body(f);
    const left = try body.branch();
    const right = try body.branch();
    const lv = try left.product(first, &.{.{ .name = "first", .value = try left.constant(u64, 1) }});
    const rv = try right.product(second, &.{.{ .name = "second", .value = try right.constant(u64, 1) }});
    try testing.expectError(error.SchemaMismatch, body.conditional(try body.constant(bool, true), try left.ret(lv), try right.ret(rv)));
    try testing.expect(c.diagnostic.expected == first);
    try testing.expect(c.diagnostic.actual == second);
}
