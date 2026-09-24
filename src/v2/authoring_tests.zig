const std = @import("std");
const source = @import("source.zig");
const a = @import("authoring.zig");
const data = @import("boundary_data");

test "ordinary declarations use distinct Zig categories" {
    comptime {
        if (a.Schema == a.Effect or a.Schema == a.Function or a.Function == a.Value or
            a.Callable == a.Effect or a.Region == a.Schema)
            @compileError("authoring categories collapsed");
    }
}

test "forward runtime choice emits one external operation and checks builder and branch scope" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const boolean = try author.scalar(bool);
    const integer = try author.scalar(u32);
    const unit = try author.scalar(void);
    const lookup = try author.external("authoring.lookup", integer, integer);
    const entry = try author.declare("entry", &.{
        .{ .name = "do_lookup", .schema = boolean },
        .{ .name = "input", .schema = integer },
    }, integer, &.{lookup});
    var body = try author.body(entry);
    const condition = try body.parameter("do_lookup");
    const input = try body.parameter("input");
    var yes = try body.child("lookup branch");
    const fetched = try yes.perform(lookup, input);
    const yes_block = try yes.finish(fetched);
    var no = try body.child("pure branch");
    try std.testing.expectError(error.OutOfScope, no.finish(fetched));
    try std.testing.expectEqual(a.Category.out_of_scope, author.diagnostic.?.category);
    const no_block = try no.finish(input);
    const joined = try body.select(condition, yes_block, no_block);
    try std.testing.expectError(error.OutOfScope, body.finish(fetched));
    try author.define(entry, try body.finish(joined));
    var compiled = try source.lower(std.testing.allocator, try author.module(entry, unit));
    defer compiled.deinit();
}

test "equal category and index from another live builder is rejected" {
    var left_raw = source.Builder.init(std.testing.allocator);
    defer left_raw.deinit();
    var right_raw = source.Builder.init(std.testing.allocator);
    defer right_raw.deinit();
    var left = a.Builder.init(&left_raw);
    var right = a.Builder.init(&right_raw);
    const left_schema = try left.scalar(u32);
    const right_schema = try right.scalar(u32);
    try std.testing.expectEqual(left_schema.id, right_schema.id);
    try std.testing.expectError(error.ForeignBuilder, right.productSchema(&.{left_schema}));
    const right_entry = try right.declare("entry", &.{}, right_schema, &.{});
    var body = try right.body(right_entry);
    try std.testing.expectError(error.ForeignBuilder, body.finish(try left.literal(u32, 1)));
    const other = try right.declare("other", &.{.{ .name = "arg", .schema = right_schema }}, right_schema, &.{});
    var other_body = try right.body(other);
    try std.testing.expectError(error.OutOfScope, body.finish(try other_body.parameter("arg")));
}

test "abandoning a body invalidates its descendant authoring handles" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const entry = try author.declare("entry", &.{}, integer, &.{});
    var body = try author.body(entry);
    var branch = try body.child("abandoned");
    var nested = try branch.child("descendant");
    branch.abandon();
    try std.testing.expectError(error.ClosedBody, nested.finish(try author.literal(u64, 1)));
    try std.testing.expectEqual(a.Category.closed_body, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("abandoned", author.diagnostic.?.entity);
}

test "copies of one body share staged effects and one finalization" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const lookup = try author.external("copy/lookup", integer, integer);
    const entry = try author.declare("entry", &.{}, integer, &.{lookup});
    var body = try author.body(entry);
    var copy = body;
    _ = try copy.perform(lookup, try author.literal(u64, 7));
    try author.define(entry, try body.finish(try author.literal(u64, 0)));
    const ignored = try author.literal(u64, 1);
    const module = try author.module(entry, unit);
    const top = module.terms[@intCast(module.functions[@intCast(entry.id)].body.?)];
    try std.testing.expect(top == .bind);
    try std.testing.expect(module.terms[@intCast(top.bind.value)] == .perform);
    try std.testing.expectError(error.ClosedBody, copy.finish(ignored));
    var compiled = try author.compile(std.testing.allocator, module);
    compiled.deinit();
}

test "derived responder interpretation retains residual external effect" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const question = try author.local("authoring/question", integer, integer, .linear);
    const lookup = try author.external("authoring/lookup", integer, integer);
    const capability = try author.capability(question);
    const responder = try author.declare("responder", &.{.{ .name = "key", .schema = integer }}, integer, &.{lookup});
    var responder_body = try author.body(responder);
    const external_reply = try responder_body.perform(lookup, try responder_body.parameter("key"));
    try author.define(responder, try responder_body.finish(external_reply));

    try std.testing.expectError(error.InvalidCapability, author.responding(question, responder, integer, &.{}, &.{ integer, capability }, .deep, .linear));
    try std.testing.expectEqual(a.Category.residual_effect_disallowed, author.diagnostic.?.category);

    const interpretation = try author.responder(question, responder, &.{lookup}, &.{ integer, capability }, .deep, .linear);

    const work = try author.declare("work", &.{
        .{ .name = "question", .schema = capability },
        .{ .name = "key", .schema = integer },
    }, integer, &.{question});
    var work_body = try author.body(work);
    const local_reply = try work_body.performLocal(question, try work_body.parameter("question"), try work_body.parameter("key"));
    try author.define(work, try work_body.finish(local_reply));

    const entry = try author.declare("entry", &.{.{ .name = "input", .schema = integer }}, integer, &.{lookup});
    var main = try author.body(entry);
    const callable = try main.lambda(work, &.{}, .reusable);
    const handled = try main.handle(interpretation, callable, &.{try main.parameter("input")}, &.{});
    try author.define(entry, try main.finish(handled));
    var compiled = try source.lower(std.testing.allocator, try author.module(entry, unit));
    defer compiled.deinit();
}

fn imageWithLabel(label: []const u8) ![]u8 {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const entry = try author.declare(label, &.{}, integer, &.{});
    var body = try author.body(entry);
    try author.define(entry, try body.finish(try author.literal(u64, 42)));
    var compiled = try author.compile(std.testing.allocator, try author.module(entry, try author.scalar(void)));
    defer compiled.deinit();
    const bytes = try std.testing.allocator.alloc(u8, try data.program_image.encodedLength(compiled.program));
    errdefer std.testing.allocator.free(bytes);
    _ = try compiled.encode(std.testing.allocator, bytes);
    return bytes;
}

test "diagnostic labels do not change executable bytes" {
    const first = try imageWithLabel("alpha label");
    defer std.testing.allocator.free(first);
    const second = try imageWithLabel("beta label");
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualSlices(u8, first, second);
}

test "runtime selected record schemas and tagged alternatives check named fields" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const boolean = try author.scalar(bool);
    var configuration = true;
    const chosen = if (configuration) integer else boolean;
    configuration = false;
    try std.testing.expect(!configuration);
    const record = try author.record(&.{.{ .name = "chosen", .schema = chosen }});
    const variant = try author.variant(&.{
        .{ .name = "missing", .schema = try author.scalar(void) },
        .{ .name = "present", .schema = integer },
    });
    const entry = try author.declare("entry", &.{.{ .name = "input", .schema = variant.schema }}, integer, &.{});
    var body = try author.body(entry);
    var missing = try body.variantCase(variant, "missing");
    const absent = try missing.finish(try author.literal(u64, 0));
    var present = try body.variantCase(variant, "present");
    const found = try present.finish(present.payload);
    const matched = try body.matchVariant(variant, try body.parameter("input"), &.{ absent, found });
    try author.define(entry, try body.finish(matched));
    var compiled = try source.lower(std.testing.allocator, try author.module(entry, try author.scalar(void)));
    defer compiled.deinit();
    var body2 = try author.ambient("field mismatch");
    try std.testing.expectError(error.TypeMismatch, body2.product(record, &.{
        .{ .name = "chosen", .value = try author.literal(bool, false) },
    }));
    try std.testing.expectEqual(a.Category.field_mismatch, author.diagnostic.?.category);
    const callable = try author.declare("expects integer", &.{
        .{ .name = "argument", .schema = integer },
    }, integer, &.{});
    try std.testing.expectError(error.TypeMismatch, body2.call(callable, &.{try author.literal(bool, false)}));
    try std.testing.expectEqual(a.Category.argument_mismatch, author.diagnostic.?.category);
}

test "named records and variants do not alias equal positional schemas" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const first = try author.record(&.{
        .{ .name = "left", .schema = integer },
        .{ .name = "right", .schema = integer },
    });
    const renamed = try author.record(&.{
        .{ .name = "right", .schema = integer },
        .{ .name = "left", .schema = integer },
    });
    const equivalent = try author.record(&.{
        .{ .name = "left", .schema = integer },
        .{ .name = "right", .schema = integer },
    });
    try std.testing.expectEqual(first.schema.id, renamed.schema.id);
    try std.testing.expect(first.schema.layout != renamed.schema.layout);
    try std.testing.expect(first.schema.layout == equivalent.schema.layout);
    var body = try author.ambient("named data");
    const value = try body.product(first, &.{
        .{ .name = "left", .value = try author.literal(u64, 11) },
        .{ .name = "right", .value = try author.literal(u64, 22) },
    });
    try std.testing.expectError(error.TypeMismatch, body.field(renamed, value, "left"));
    try std.testing.expectEqual(a.Category.field_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("named record layout", author.diagnostic.?.relationship.?);
    _ = try body.field(equivalent, value, "left");
    const accepts_renamed = try author.declare("renamed argument", &.{
        .{ .name = "record", .schema = renamed.schema },
    }, integer, &.{});
    try std.testing.expectError(error.TypeMismatch, body.call(accepts_renamed, &.{value}));
    try std.testing.expectError(error.TypeMismatch, body.apply(try body.lambda(accepts_renamed, &.{}, .reusable), &.{value}));
    const question = try author.local("record/question", integer, first.schema, .linear);
    const h = try author.interpret(.{ .operation = question, .input = first.schema, .answer = first.schema, .mode = .deep, .use = .linear });
    const wrong_body = try author.declare("wrong handled body", &.{}, renamed.schema, &.{});
    try std.testing.expectError(error.TypeMismatch, body.handle(h, try body.lambda(wrong_body, &.{}, .reusable), &.{}, &.{}));
    var clause = try author.body(h.clause);
    const renamed_value = try clause.product(renamed, &.{
        .{ .name = "right", .value = try author.literal(u64, 3) },
        .{ .name = "left", .value = try author.literal(u64, 4) },
    });
    try std.testing.expectError(error.TypeMismatch, clause.resumeValue(try clause.parameter("resume"), renamed_value));

    const left = try author.variant(&.{
        .{ .name = "left", .schema = integer },
        .{ .name = "right", .schema = integer },
    });
    const right = try author.variant(&.{
        .{ .name = "right", .schema = integer },
        .{ .name = "left", .schema = integer },
    });
    try std.testing.expectEqual(left.schema.id, right.schema.id);
    const tagged = try body.inject(left, "left", try author.literal(u64, 7));
    var a_case = try body.variantCase(right, "right");
    const a_branch = try a_case.finish(a_case.payload);
    var b_case = try body.variantCase(right, "left");
    const b_branch = try b_case.finish(b_case.payload);
    try std.testing.expectError(error.TypeMismatch, body.matchVariant(right, tagged, &.{ a_branch, b_branch }));
    try std.testing.expectEqual(a.Category.branch_mismatch, author.diagnostic.?.category);
    try std.testing.expectError(error.InvalidBranch, body.matchVariant(left, tagged, &.{ a_branch, b_branch }));
    try std.testing.expectEqualStrings("named variant layout", author.diagnostic.?.relationship.?);
    var yes = try body.child("first layout");
    const yes_result = try yes.finish(value);
    var no = try body.child("other layout");
    const no_result = try no.finish(try no.product(renamed, &.{
        .{ .name = "right", .value = try author.literal(u64, 1) },
        .{ .name = "left", .value = try author.literal(u64, 2) },
    }));
    try std.testing.expectError(error.TypeMismatch, body.select(try author.literal(bool, true), yes_result, no_result));
}

test "named record layout survives direct calls and callable application" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const record = try author.record(&.{
        .{ .name = "left", .schema = integer },
        .{ .name = "right", .schema = integer },
    });
    const identity = try author.declare("identity", &.{
        .{ .name = "record", .schema = record.schema },
    }, record.schema, &.{});
    var identity_body = try author.body(identity);
    try author.define(identity, try identity_body.finish(try identity_body.parameter("record")));
    const entry = try author.declare("entry", &.{}, integer, &.{});
    var body = try author.body(entry);
    const value = try body.product(record, &.{
        .{ .name = "left", .value = try author.literal(u64, 11) },
        .{ .name = "right", .value = try author.literal(u64, 22) },
    });
    const directly = try body.call(identity, &.{value});
    const applied = try body.apply(try body.lambda(identity, &.{}, .reusable), &.{value});
    const sum = try body.checkedAdd(try body.field(record, directly, "left"), try body.field(record, applied, "right"), try author.literal(void, {}));
    try author.define(entry, try body.finish(sum));
    var compiled = try author.compile(std.testing.allocator, try author.module(entry, try author.scalar(void)));
    compiled.deinit();
}

test "nested closure capture is scoped and bounded by its declared permission" {
    for ([_]bool{ true, false }) |allowed| {
        var raw = source.Builder.init(std.testing.allocator);
        defer raw.deinit();
        var author = a.Builder.init(&raw);
        const integer = try author.scalar(u64);
        const entry = try author.declare("outer", &.{.{ .name = "value", .schema = integer }}, integer, &.{});
        var outer = try author.body(entry);
        const captured = try outer.parameter("value");
        const inner = try author.declare("nested", &.{}, integer, &.{});
        var nested = try author.bodyWithin(&outer, inner);
        try author.define(inner, try nested.finish(captured));
        const closure = try outer.lambda(inner, if (allowed) &.{integer} else &.{}, .reusable);
        const result = try outer.apply(closure, &.{});
        try author.define(entry, try outer.finish(result));
        const module = try author.module(entry, try author.scalar(void));
        if (allowed) {
            var compiled = try author.compile(std.testing.allocator, module);
            compiled.deinit();
        } else {
            try std.testing.expectError(error.InvalidOwnership, author.compile(std.testing.allocator, module));
            try std.testing.expectEqual(a.Category.ownership_use, author.diagnostic.?.category);
            try std.testing.expect(author.diagnostic.?.source_detail != null);
            try std.testing.expect(!std.mem.eql(u8, author.diagnostic.?.entity, "source declaration"));
        }
    }
}

fn allocationAttempt(allocator: std.mem.Allocator) !void {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const boolean = try author.scalar(bool);
    const input = try author.record(&.{.{ .name = "number", .schema = integer }});
    const variant = try author.variant(&.{
        .{ .name = "none", .schema = try author.scalar(void) },
        .{ .name = "some", .schema = integer },
    });
    _ = variant;
    const lookup = try author.external("allocation/lookup", integer, integer);
    const entry = try author.declare("allocation entry", &.{
        .{ .name = "query", .schema = boolean },
        .{ .name = "record", .schema = input.schema },
    }, integer, &.{lookup});
    var body = try author.body(entry);
    const number = try body.field(input, try body.parameter("record"), "number");
    var yes = try body.child("request");
    const requested = try yes.perform(lookup, number);
    var no = try body.child("pure");
    const selected = try body.select(try body.parameter("query"), try yes.finish(requested), try no.finish(number));
    try author.define(entry, try body.finish(selected));
    var compiled = try author.compile(allocator, try author.module(entry, try author.scalar(void)));
    defer compiled.deinit();
    const bytes = try allocator.alloc(u8, try data.program_image.encodedLength(compiled.program));
    defer allocator.free(bytes);
    _ = try compiled.encode(allocator, bytes);
    try std.testing.expectEqualStrings("ABL_BPI3", bytes[0..8]);
}

test "authoring constructors and finalization release each failed allocation" {
    try allocationAttempt(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationAttempt, .{});
}

test "one-shot callable admits mutually exclusive uses and rejects sequential duplication" {
    for ([_]bool{ true, false }) |exclusive| {
        var raw = source.Builder.init(std.testing.allocator);
        defer raw.deinit();
        var author = a.Builder.init(&raw);
        const integer = try author.scalar(u64);
        const boolean = try author.scalar(bool);
        const pair = try author.record(&.{
            .{ .name = "first", .schema = integer },
            .{ .name = "second", .schema = integer },
        });
        const work = try author.declare("one shot", &.{}, integer, &.{});
        var work_body = try author.body(work);
        try author.define(work, try work_body.finish(try author.literal(u64, 9)));
        const entry = try author.declare("entry", &.{.{ .name = "side", .schema = boolean }}, if (exclusive) integer else pair.schema, &.{});
        var body = try author.body(entry);
        const callable = try body.asCallable(try body.bindValue((try body.lambda(work, &.{}, .linear)).value));
        const result = if (exclusive) blk: {
            var yes = try body.child("yes");
            const left = try yes.apply(callable, &.{});
            var no = try body.child("no");
            const right = try no.apply(callable, &.{});
            break :blk try body.select(try body.parameter("side"), try yes.finish(left), try no.finish(right));
        } else blk: {
            const first = try body.apply(callable, &.{});
            const second = try body.apply(callable, &.{});
            break :blk try body.product(pair, &.{
                .{ .name = "first", .value = first },
                .{ .name = "second", .value = second },
            });
        };
        try author.define(entry, try body.finish(result));
        const module = try author.module(entry, try author.scalar(void));
        if (exclusive) {
            var compiled = try author.compile(std.testing.allocator, module);
            compiled.deinit();
        } else {
            try std.testing.expectError(error.UnavailableSlot, author.compile(std.testing.allocator, module));
            try std.testing.expectEqual(a.Category.ownership_use, author.diagnostic.?.category);
            try std.testing.expect(!std.mem.eql(u8, author.diagnostic.?.entity, "source declaration"));
        }
    }
}

test "reusable closure cannot capture a bound one-shot callable" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const one_shot = try author.declare("one shot", &.{}, integer, &.{});
    var work_body = try author.body(one_shot);
    try author.define(one_shot, try work_body.finish(try author.literal(u64, 9)));
    const entry = try author.declare("entry", &.{}, integer, &.{});
    var outer = try author.body(entry);
    const owned = try outer.asCallable(try outer.bindValue((try outer.lambda(one_shot, &.{}, .linear)).value));
    const nested = try author.declare("reusable nested", &.{}, integer, &.{});
    var inner = try author.bodyWithin(&outer, nested);
    const result = try inner.apply(owned, &.{});
    try author.define(nested, try inner.finish(result));
    const reused = try outer.lambda(nested, &.{owned.value.schema}, .reusable);
    const answer = try outer.apply(reused, &.{});
    try author.define(entry, try outer.finish(answer));
    const module = try author.module(entry, try author.scalar(void));
    if (author.compile(std.testing.allocator, module)) |compiled| {
        var unexpected = compiled;
        unexpected.deinit();
        return error.ExpectedOwnershipRejection;
    } else |err| {
        try std.testing.expect(err == error.InvalidOwnership or err == error.UnavailableSlot);
        try std.testing.expectEqual(a.Category.ownership_use, author.diagnostic.?.category);
    }
}

test "handler answer and resumption diagnostics retain causal labels" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const question = try author.local("question", integer, integer, .linear);
    const interpretation = try author.interpret(.{
        .operation = question,
        .input = integer,
        .answer = integer,
        .mode = .deep,
        .use = .linear,
    });
    var returns = try author.body(interpretation.returns);
    try std.testing.expectError(error.TypeMismatch, author.define(interpretation.returns, try returns.finish(try author.literal(bool, false))));
    try std.testing.expectEqual(a.Category.schema_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("handler return", author.diagnostic.?.entity);
    var clause = try author.body(interpretation.clause);
    try std.testing.expectError(error.TypeMismatch, clause.resumeValue(try clause.parameter("resume"), try author.literal(bool, false)));
    try std.testing.expectEqualStrings("resumption input", author.diagnostic.?.entity);
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try author.diagnostic.?.render(&output.writer);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "expected schema") != null);
}

test "scoped operation checks its named body schema" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const boolean = try author.scalar(bool);
    const unit = try author.scalar(void);
    const expected = try author.declare("expected body", &.{}, integer, &.{});
    const body_schema = try author.callableSchema(expected, &.{}, .reusable);
    const operation = try author.scopedLocal("scoped", unit, integer, &.{.{ .name = "body", .schema = body_schema }}, &.{}, .linear);
    const capability = try author.capability(operation);
    const wrong = try author.declare("wrong body", &.{}, boolean, &.{});
    const entry = try author.declare("entry", &.{
        .{ .name = "cap", .schema = capability },
    }, integer, &.{operation});
    var body = try author.body(entry);
    try std.testing.expectError(error.TypeMismatch, body.performScoped(operation, try body.parameter("cap"), try author.literal(void, {}), &.{try body.lambda(wrong, &.{}, .reusable)}, &.{}));
    try std.testing.expectEqual(a.Category.argument_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("body", author.diagnostic.?.entity);
}

test "shallow resumption answer is handled input while outer answer may change" {
    for ([_]bool{ false, true }) |shallow| {
        var raw = source.Builder.init(std.testing.allocator);
        defer raw.deinit();
        var author = a.Builder.init(&raw);
        const integer = try author.scalar(u64);
        const unit = try author.scalar(void);
        const pair = try author.record(&.{
            .{ .name = "value", .schema = integer },
            .{ .name = "tag", .schema = integer },
        });
        const operation = try author.local("answer/change", unit, integer, .affine);
        const cap = try author.capability(operation);
        const h = try author.interpret(.{ .operation = operation, .input = integer, .answer = pair.schema, .mode = if (shallow) .shallow else .deep, .use = .affine, .resumption_effects = if (shallow) &.{operation} else &.{} });
        const token = raw.schemas.items[@intCast(h.resumption.id)].internal.resumption;
        try std.testing.expectEqual(if (shallow) integer.id else pair.schema.id, token.answer);
        var returns = try author.body(h.returns);
        const value = try returns.parameter("value");
        try author.define(h.returns, try returns.finish(try returns.product(pair, &.{
            .{ .name = "value", .value = value },
            .{ .name = "tag", .value = try author.literal(u64, 99) },
        })));
        var clause = try author.body(h.clause);
        try author.define(h.clause, try clause.finish(try clause.product(pair, &.{
            .{ .name = "value", .value = try author.literal(u64, 7) },
            .{ .name = "tag", .value = try author.literal(u64, 99) },
        })));
        const work = try author.declare("work", &.{
            .{ .name = "cap", .schema = cap },
        }, integer, &.{operation});
        var work_body = try author.body(work);
        const performed = try work_body.performLocal(operation, try work_body.parameter("cap"), try author.literal(void, {}));
        try author.define(work, try work_body.finish(performed));
        const entry = try author.declare("entry", &.{}, pair.schema, &.{});
        var body = try author.body(entry);
        const handled = try body.handle(h, try body.lambda(work, &.{}, .reusable), &.{}, &.{});
        try author.define(entry, try body.finish(handled));
        var compiled = try author.compile(std.testing.allocator, try author.module(entry, unit));
        compiled.deinit();
    }
}

test "shallow continuation accepts a deep successor" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const operation = try author.local("successor", unit, integer, .linear);
    const cap = try author.capability(operation);
    const first = try author.interpret(.{ .operation = operation, .input = integer, .answer = integer, .mode = .shallow, .use = .linear, .resumption_effects = &.{operation} });
    const next = try author.interpret(.{ .operation = operation, .input = integer, .answer = integer, .mode = .deep, .use = .linear });
    for ([_]a.Interpretation{ first, next }) |h| {
        var returns = try author.body(h.returns);
        try author.define(h.returns, try returns.finish(try returns.parameter("value")));
    }
    var next_clause = try author.body(next.clause);
    const continued = try next_clause.resumeValue(try next_clause.parameter("resume"), try author.literal(u64, 7));
    try author.define(next.clause, try next_clause.finish(continued));
    var first_clause = try author.body(first.clause);
    const switched = try first_clause.resumeWith(try first_clause.parameter("resume"), try author.literal(u64, 7), next, &.{});
    try author.define(first.clause, try first_clause.finish(switched));
    const work = try author.declare("work", &.{.{ .name = "cap", .schema = cap }}, integer, &.{operation});
    var work_body = try author.body(work);
    const requested = try work_body.performLocal(operation, try work_body.parameter("cap"), try author.literal(void, {}));
    try author.define(work, try work_body.finish(requested));
    const entry = try author.declare("entry", &.{}, integer, &.{});
    var body = try author.body(entry);
    const handled = try body.handle(first, try body.lambda(work, &.{}, .reusable), &.{}, &.{});
    try author.define(entry, try body.finish(handled));
    var compiled = try author.compile(std.testing.allocator, try author.module(entry, unit));
    compiled.deinit();
}

test "resumption computation accepts declared use-site capability parameters" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const raised = try author.local("raised", unit, unit, .linear);
    const raised_cap = try author.capability(raised);
    const asking = try author.scopedLocal("asking", unit, integer, &.{}, &.{raised}, .linear);
    const h = try author.interpret(.{ .operation = asking, .input = integer, .answer = integer, .mode = .deep, .use = .linear });
    var returns = try author.body(h.returns);
    try author.define(h.returns, try returns.finish(try returns.parameter("value")));
    const thunk = try author.declare("injected", &.{
        .{ .name = "raised", .schema = raised_cap },
    }, integer, &.{});
    var thunk_body = try author.body(thunk);
    try author.define(thunk, try thunk_body.finish(try author.literal(u64, 42)));
    var clause = try author.body(h.clause);
    const wrong = try author.declare("missing use-site capability", &.{}, integer, &.{});
    var wrong_body = try author.body(wrong);
    try author.define(wrong, try wrong_body.finish(try author.literal(u64, 0)));
    try std.testing.expectError(error.TypeMismatch, clause.resumeComputation(try clause.parameter("resume"), try clause.lambda(wrong, &.{}, .reusable)));
    const result = try clause.resumeComputation(try clause.parameter("resume"), try clause.lambda(thunk, &.{}, .reusable));
    try author.define(h.clause, try clause.finish(result));
    const entry = try author.declare("entry", &.{}, integer, &.{});
    var body = try author.body(entry);
    try author.define(entry, try body.finish(try author.literal(u64, 1)));
    var compiled = try author.compile(std.testing.allocator, try author.module(entry, unit));
    compiled.deinit();
}

test "explicit diagnostic snapshot remains accurate across teardown and later errors" {
    var raw = source.Builder.init(std.testing.allocator);
    var alive = true;
    defer if (alive) raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const entry = try author.declare("bad call", &.{
        .{ .name = "value", .schema = integer },
    }, integer, &.{});
    var body = try author.body(entry);
    const callee = try author.declare("expects integer", &.{
        .{ .name = "value", .schema = integer },
    }, integer, &.{});
    try std.testing.expectError(error.TypeMismatch, body.call(callee, &.{try author.literal(bool, false)}));
    var owned = try a.OwnedDiagnostic.copy(std.testing.allocator, author.diagnostic orelse return error.MissingDiagnostic);
    defer owned.deinit();
    try std.testing.expectError(error.InvalidArgument, body.parameter("missing"));
    try std.testing.expect(author.diagnostic == null);
    raw.deinit();
    alive = false;
    try std.testing.expectEqual(a.Category.argument_mismatch, owned.detail.category);
    try std.testing.expectEqualStrings("expects integer", owned.detail.entity);
    var text: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer text.deinit();
    try owned.detail.render(&text.writer);
    try std.testing.expect(std.mem.indexOf(u8, text.written(), "argument_mismatch") != null);
}

fn diagnosticCopyAttempt(allocator: std.mem.Allocator) !void {
    var owned = try a.OwnedDiagnostic.copy(allocator, .{
        .category = .out_of_scope,
        .entity = "branch value",
        .introduced_in = "left",
        .used_in = "right",
    });
    defer owned.deinit();
    try std.testing.expectEqualStrings("branch value", owned.detail.entity);
}

test "diagnostic ownership handles every failed allocation" {
    try diagnosticCopyAttempt(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, diagnosticCopyAttempt, .{});
}

test "an exhausted authoring builder cannot publish a Module" {
    var bytes: [16 * 1024]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&bytes);
    var raw = source.Builder.init(fixed.allocator());
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const entry = try author.declare("entry", &.{}, integer, &.{});
    var body = try author.body(entry);
    try author.define(entry, try body.finish(try author.literal(u64, 1)));
    var exhausted = false;
    for (0..10_000) |_| {
        _ = author.declare("allocation pressure", &.{}, integer, &.{}) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            exhausted = true;
            break;
        };
    }
    try std.testing.expect(exhausted);
    try std.testing.expect(author.poisoned);
    try std.testing.expectError(error.InvalidSource, author.module(entry, unit));
}
