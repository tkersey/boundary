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
    const entry = try c.function("entry", &.{.{ .name = "choose", .schema = try c.scalar(bool) }}, integer, &.{});
    const body = try c.body(entry);
    const owned = try body.lambda(work, once);
    const result = if (sequential) blk: {
        _ = try body.apply(owned, &.{});
        break :blk try body.apply(owned, &.{});
    } else blk: {
        const left = try body.branch();
        const right = try body.branch();
        break :blk try body.conditional(try body.parameter("choose"), try left.ret(try left.apply(owned, &.{})), try right.ret(try right.apply(owned, &.{})));
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

fn shallowResidual(allocator: std.mem.Allocator, allow_escape: bool) !void {
    var raw = source.Builder.init(allocator);
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
        .mode = .shallow,
        .use = .linear,
        .residual = &.{ lookup, question },
        .escaping = if (allow_escape) &.{lookup} else &.{},
        .captures = &.{},
    });
    const schema = try c.handledSchema(h);
    const work = try c.functionFor("work", schema);
    const body = try c.body(work);
    try c.define(work, try body.ret(try body.performLocal(question, try body.parameter("capability"), try body.constant(u64, 19))));
    const entry = try c.function("entry", &.{}, integer, &.{ lookup, question });
    const entry_body = try c.body(entry);
    try c.define(entry, try entry_body.ret(try entry_body.handleWith(h, try entry_body.lambda(work, schema), &.{})));
    var compiled = try c.compile(allocator, entry, unit);
    defer compiled.deinit();
}
test "A06 A09 shallow residual external effects need an explicit escaping allowance" {
    try shallowResidual(testing.allocator, true);
    try testing.expectError(error.InvalidEffect, shallowResidual(testing.allocator, false));
}

fn oneShotVariant(allocator: std.mem.Allocator, twice: bool) !void {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const once = try c.callable(&.{}, unit, &.{}, .{ .use = .linear, .captures = &.{} });
    const sum = try c.alternatives(&.{ .{ .name = "empty", .schema = unit }, .{ .name = "owned", .schema = once } });
    const entry = try c.function("entry", &.{}, unit, &.{});
    const body = try c.body(entry);
    const value = try body.variant(sum, "empty", try body.constant(void, {}));
    var result = try body.constant(void, {});
    for (0..@as(usize, if (twice) 2 else 1)) |_| {
        const empty = try body.caseOf(value, "empty");
        const owned = try body.caseOf(value, "owned");
        const used = try owned.body().apply(owned.payload(), &.{});
        result = try body.match(value, &.{ try empty.ret(empty.payload()), try owned.ret(used) });
    }
    try c.define(entry, try body.ret(result));
    var compiled = try c.compile(allocator, entry, unit);
    defer compiled.deinit();
}
test "A08 symbolic one-shot aggregate construction does not repeat at each use" {
    try oneShotVariant(testing.allocator, false);
    try testing.expectError(error.UnavailableSlot, oneShotVariant(testing.allocator, true));
}

test "review named cleanup descriptors retain both supplied failure layouts" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const integer = try c.scalar(u64);
    const failure = try c.record(&.{.{ .name = "code", .schema = integer }});
    const other = try c.record(&.{.{ .name = "other", .schema = integer }});
    const info = try c.cleanupInfo(failure);
    const other_info = try c.cleanupInfo(other);
    try testing.expect(info.fields()[0].schema.fields()[1].schema == failure);
    try testing.expect(info.fields()[2].schema.resultSchema().? == failure);
    try testing.expect(other_info.fields()[0].schema.fields()[1].schema == other);
    try testing.expect(info.fields()[0].schema.fields()[1].schema == failure);
    const raw_info = try @import("library/cleanup.zig").exitInfo(&raw, try a.interop.schemaId(c, failure));
    try testing.expectEqual(raw_info, try a.interop.schemaId(c, info));
    const entry = try c.function("inspect cleanup", &.{.{ .name = "exit", .schema = info }}, integer, &.{});
    const body = try c.body(entry);
    const primary = try body.field(try body.parameter("exit"), "0");
    var cases: [4]*const a.FinishedCase = undefined;
    for ([_][]const u8{ "0", "1", "2", "3" }, 0..) |name, index| {
        const arm = try body.caseOf(primary, name);
        const result = if (index == 1) try arm.body().field(arm.payload(), "code") else try arm.body().constant(u64, 0);
        cases[index] = try arm.ret(result);
    }
    try c.define(entry, try body.ret(try body.match(primary, &cases)));
    var compiled = try c.compile(testing.allocator, entry, try c.scalar(void));
    defer compiled.deinit();
}

fn importedSequence(allocator: std.mem.Allocator) !void {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const sequence = try c.sequence(unit);
    const imported = try a.interop.schema(c, try a.interop.schemaId(c, sequence));
    const entry = try c.function("compatible sequence", &.{.{ .name = "items", .schema = imported }}, sequence, &.{});
    const body = try c.body(entry);
    const result = try body.concat(try body.parameter("items"), try body.sequenceValue(sequence, &.{}));
    try c.define(entry, try body.ret(result));
    _ = try c.module(entry, unit);
}
test "review compatible imported sequences compose and tolerate allocation failures" {
    try testing.checkAllAllocationFailures(testing.allocator, importedSequence, .{});
}

test "review shared schema graph comparison does not unfold a binary tree" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    var schema = unit;
    for (0..28) |_| schema = try c.record(&.{ .{ .name = "0", .schema = schema }, .{ .name = "1", .schema = schema } });
    const imported = try a.interop.schema(c, try a.interop.schemaId(c, schema));
    const consume = try c.function("consume", &.{.{ .name = "value", .schema = schema }}, unit, &.{});
    const consume_body = try c.body(consume);
    try c.define(consume, try consume_body.ret(try consume_body.constant(void, {})));
    const entry = try c.function("entry", &.{.{ .name = "value", .schema = imported }}, unit, &.{});
    const body = try c.body(entry);
    try c.define(entry, try body.ret(try body.call(consume, &.{.{ .name = "value", .value = try body.parameter("value") }})));
    // 29 schema nodes describe 2^28 unit leaves; comparison must visit shared pairs once.
    try testing.expectEqual(@as(usize, 29), raw.schemas.items.len);
}

test "review equal raw schemas still reject different nested field names" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const named = try c.record(&.{.{ .name = "code", .schema = try c.scalar(u64) }});
    const expected = try c.sequence(named);
    const imported = try a.interop.schema(c, try a.interop.schemaId(c, expected));
    const f = try c.function("expects names", &.{.{ .name = "value", .schema = expected }}, unit, &.{});
    const entry = try c.function("entry", &.{.{ .name = "value", .schema = imported }}, unit, &.{});
    const body = try c.body(entry);
    try testing.expectError(error.SchemaMismatch, body.call(f, &.{.{ .name = "value", .value = try body.parameter("value") }}));
}

test "review importing a scoped operation preserves its operand and clause interface" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    var compiled = try source.lower(testing.allocator, try @import("authoring_cases.zig").build(&raw, .imported_scoped));
    defer compiled.deinit();
}

test "review borrowed and recursive callable metadata compose across imports" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const region = try c.region();
    const loan = try c.borrowed(unit, region);
    const imported_loan = try a.interop.schema(c, try a.interop.schemaId(c, loan));
    const consume = try c.function("consume loan", &.{.{ .name = "loan", .schema = loan }}, unit, &.{});
    const caller = try c.function("caller", &.{.{ .name = "loan", .schema = imported_loan }}, unit, &.{});
    const body = try c.body(caller);
    _ = try body.call(consume, &.{.{ .name = "loan", .value = try body.parameter("loan") }});
    const recursive_id = try raw.reserveSchema();
    try raw.defineSchema(recursive_id, .{ .internal = .{ .computation = .{
        .parameters = &.{recursive_id},
        .result = try a.interop.schemaId(c, unit),
    } } });
    const recursive = try a.interop.schema(c, recursive_id);
    const equivalent = try c.callable(recursive.fields(), unit, &.{}, .{ .use = .reusable, .captures = &.{} });
    const target = try c.function("recursive consumer", &.{.{ .name = "f", .schema = recursive }}, unit, &.{});
    const input = try c.function("recursive input", &.{.{ .name = "f", .schema = equivalent }}, unit, &.{});
    const input_body = try c.body(input);
    _ = try input_body.call(target, &.{.{ .name = "f", .value = try input_body.parameter("f") }});
}

fn namedFaultPublication(allocator: std.mem.Allocator, mismatch: bool, late: bool, abandoned: bool) !void {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const integer = try c.scalar(u64);
    const declared = try c.record(&.{.{ .name = "code", .schema = integer }});
    const actual = if (mismatch) try c.record(&.{.{ .name = "other", .schema = integer }}) else declared;
    const entry = try c.function("entry", &.{}, integer, &.{});
    const body = try c.body(entry);
    if (late) try c.define(entry, try body.ret(try body.constant(u64, 42)));
    const target = if (late) try c.function("late helper", &.{}, integer, &.{}) else entry;
    const work = if (late) try c.body(target) else if (abandoned) try body.branch() else body;
    const literal = try raw.literal(.{ .schema = try a.interop.schemaId(c, actual), .bytes = &.{ 9, 0, 0, 0, 0, 0, 0, 0 } });
    const failure = try a.interop.adoptValue(work, literal, actual);
    const result = try work.checkedAdd(try work.constant(u64, 1), try work.constant(u64, 2), failure);
    if (abandoned) {
        work.abandon();
        try c.define(entry, try body.ret(try body.constant(u64, 42)));
    } else try c.define(target, try work.ret(result));
    var compiled = try c.compile(allocator, entry, declared);
    defer compiled.deinit();
}
test "review publication checks named faults including later helpers and ignores abandoned work" {
    try namedFaultPublication(testing.allocator, false, false, false);
    try namedFaultPublication(testing.allocator, false, true, false);
    try testing.expectError(error.SchemaMismatch, namedFaultPublication(testing.allocator, true, false, false));
    try testing.expectError(error.SchemaMismatch, namedFaultPublication(testing.allocator, true, true, false));
    try namedFaultPublication(testing.allocator, true, false, true);
}

fn namedCleanupPublication(allocator: std.mem.Allocator, mismatch: bool) !void {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const integer = try c.scalar(u64);
    const declared = try c.record(&.{.{ .name = "code", .schema = integer }});
    const actual = if (mismatch) try c.record(&.{.{ .name = "other", .schema = integer }}) else declared;
    const work_schema = try c.callable(&.{}, integer, &.{}, .{ .use = .linear, .captures = &.{} });
    const work = try c.functionFor("work", work_schema);
    const work_body = try c.body(work);
    try c.define(work, try work_body.ret(try work_body.constant(u64, 42)));
    const cleanup_schema = try c.callable(&.{.{ .name = "exit", .schema = try c.cleanupInfo(actual) }}, unit, &.{}, .{ .use = .linear, .captures = &.{} });
    const cleanup = try c.functionFor("cleanup", cleanup_schema);
    const cleanup_body = try c.body(cleanup);
    try c.define(cleanup, try cleanup_body.ret(try cleanup_body.constant(void, {})));
    const entry = try c.function("entry", &.{}, integer, &.{});
    const body = try c.body(entry);
    try c.define(entry, try body.ret(try body.protect(try body.lambda(work, work_schema), try body.lambda(cleanup, cleanup_schema), &.{})));
    var compiled = try c.compile(allocator, entry, declared);
    defer compiled.deinit();
}
test "review publication checks cleanup failure interpretation" {
    try namedCleanupPublication(testing.allocator, false);
    try testing.expectError(error.SchemaMismatch, namedCleanupPublication(testing.allocator, true));
}

test "review callable and resumption compatibility retain named capture bounds" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const integer = try c.scalar(u64);
    const left = try c.record(&.{.{ .name = "left", .schema = integer }});
    const right = try c.record(&.{.{ .name = "right", .schema = integer }});
    const first = try c.callable(&.{}, unit, &.{}, .{ .use = .reusable, .captures = &.{left} });
    const second = try c.callable(&.{}, unit, &.{}, .{ .use = .reusable, .captures = &.{right} });
    const use = try c.function("use", &.{.{ .name = "work", .schema = first }}, unit, &.{});
    const entry = try c.function("entry", &.{.{ .name = "work", .schema = second }}, unit, &.{});
    const body = try c.body(entry);
    try testing.expectError(error.SchemaMismatch, body.call(use, &.{.{ .name = "work", .value = try body.parameter("work") }}));
    // The failed construction is intentionally followed only by teardown.
}

test "review twice rejection replaces stale diagnostics with its own relationship" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const linear = try c.callable(&.{}, unit, &.{}, .{ .use = .linear, .captures = &.{} });
    c.diagnostic = .{ .code = error.UnknownName, .entity = "earlier", .relationship = "stale" };
    try testing.expectError(error.InvalidOwnership, c.twice(linear));
    try testing.expectEqual(error.InvalidOwnership, c.diagnostic.code.?);
    try testing.expectEqualStrings("twice", c.diagnostic.entity);
    const rendered = try c.diagnostic.renderAlloc(testing.allocator);
    defer testing.allocator.free(rendered);
    try testing.expect(std.mem.indexOf(u8, rendered, "reusable zero-argument") != null);
}

fn publicationAllocation(allocator: std.mem.Allocator) !void {
    try namedFaultPublication(allocator, false, true, false);
    try namedCleanupPublication(allocator, false);
}
test "review publication metadata and traversal tolerate allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, publicationAllocation, .{});
}

test "review resumption capture contracts preserve nested names" {
    var raw = source.Builder.init(testing.allocator);
    defer raw.deinit();
    const c = try a.Context.init(&raw);
    const unit = try c.scalar(void);
    const integer = try c.scalar(u64);
    const left = try c.record(&.{.{ .name = "left", .schema = integer }});
    const right = try c.record(&.{.{ .name = "right", .schema = integer }});
    const operation = try c.local("capture", unit, unit, .multi);
    const first = try c.handler(operation, unit, unit, .{ .mode = .deep, .use = .multi, .residual = &.{}, .captures = &.{left} });
    const second = try c.handler(operation, unit, unit, .{ .mode = .deep, .use = .multi, .residual = &.{}, .captures = &.{right} });
    const first_token = try a.interop.resumptionSchema(c, first);
    const second_token = try a.interop.resumptionSchema(c, second);
    const use = try c.function("use", &.{.{ .name = "token", .schema = first_token }}, unit, &.{});
    const caller = try c.function("caller", &.{.{ .name = "token", .schema = second_token }}, unit, &.{});
    const body = try c.body(caller);
    try testing.expectError(error.SchemaMismatch, body.call(use, &.{.{ .name = "token", .value = try body.parameter("token") }}));
}
