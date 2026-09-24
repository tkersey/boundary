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
    var compiled = try author.compile(std.testing.allocator, try author.module(entry, unit));
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
    const raw_view = raw.module(entry.id, unit.id);
    const top = raw_view.terms[@intCast(raw_view.functions[@intCast(entry.id)].body.?)];
    try std.testing.expect(top == .bind);
    try std.testing.expect(raw_view.terms[@intCast(top.bind.value)] == .perform);
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
    var compiled = try author.compile(std.testing.allocator, try author.module(entry, unit));
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
    var compiled = try author.compile(std.testing.allocator, try author.module(entry, try author.scalar(void)));
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
    try std.testing.expect(!@hasField(a.Record, "fields"));
    try std.testing.expect(!@hasField(a.Variant, "alternatives"));
    try std.testing.expect(!@hasField(a.FinishedCase, "index"));
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
    var relabeled = value;
    relabeled.schema = renamed.schema;
    try std.testing.expectError(error.TypeMismatch, body.field(renamed, relabeled, "left"));
    try std.testing.expectEqual(a.Category.schema_mismatch, author.diagnostic.?.category);
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
    const right_tagged = try body.inject(right, "right", try author.literal(u64, 8));
    var swapped_origin = a_branch;
    swapped_origin.origin = b_branch.origin;
    try std.testing.expectError(error.InvalidBranch, body.matchVariant(right, right_tagged, &.{ swapped_origin, b_branch }));
    try std.testing.expectEqual(a.Category.branch_mismatch, author.diagnostic.?.category);
    _ = try body.matchVariant(right, right_tagged, &.{ a_branch, b_branch });
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

test "foreign effect rejection records its diagnostic" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    var other_raw = source.Builder.init(std.testing.allocator);
    defer other_raw.deinit();
    var other = a.Builder.init(&other_raw);
    const other_integer = try other.scalar(u64);
    const foreign = try other.external("foreign/lookup", other_integer, other_integer);
    var body = try author.ambient("foreign effect");
    try std.testing.expectError(error.ForeignBuilder, body.perform(foreign, try author.literal(u64, 7)));
    try std.testing.expectEqual(a.Category.foreign_builder, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("effect", author.diagnostic.?.entity);
}

test "function declarations retain their issued named signatures" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const first = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const renamed = try author.record(&.{
        .{ .name = "b", .schema = integer },
        .{ .name = "a", .schema = integer },
    });
    const function = try author.declare("named result", &.{}, first.schema, &.{});
    var relabeled = function;
    relabeled.result = renamed.schema;
    try std.testing.expectError(error.TypeMismatch, author.body(relabeled));
    try std.testing.expectEqual(a.Category.schema_mismatch, author.diagnostic.?.category);
    var ambient = try author.ambient("caller");
    try std.testing.expectError(error.TypeMismatch, ambient.call(relabeled, &.{}));
    const other = try author.declare("other function", &.{.{ .name = "value", .schema = integer }}, first.schema, &.{});
    var misplaced = try author.body(function);
    misplaced.function = other;
    try std.testing.expectError(error.InvalidBranch, misplaced.parameter("value"));
    try std.testing.expectEqual(a.Category.out_of_scope, author.diagnostic.?.category);
    var valid = try author.body(function);
    const value = try valid.product(first, &.{
        .{ .name = "a", .value = try author.literal(u64, 1) },
        .{ .name = "b", .value = try author.literal(u64, 2) },
    });
    try author.define(function, try valid.finish(value));
}

test "callable arity failures retain structured counts" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const function = try author.declare("one argument", &.{.{ .name = "value", .schema = integer }}, integer, &.{});
    var body = try author.ambient("arity caller");
    try std.testing.expectError(error.InvalidArgument, body.call(function, &.{}));
    try std.testing.expectEqual(a.Category.argument_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqual(@as(usize, 1), author.diagnostic.?.expected_count.?);
    try std.testing.expectEqual(@as(usize, 0), author.diagnostic.?.actual_count.?);
    const callable = try body.lambda(function, &.{}, .reusable);
    try std.testing.expectError(error.InvalidArgument, body.apply(callable, &.{}));
    try std.testing.expectEqual(a.Category.argument_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("callable application", author.diagnostic.?.entity);
    try std.testing.expectEqual(@as(usize, 1), author.diagnostic.?.expected_count.?);
    try std.testing.expectEqual(@as(usize, 0), author.diagnostic.?.actual_count.?);
}

test "effect declarations reject named payload relabeling" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const left = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const right = try author.record(&.{
        .{ .name = "b", .schema = integer },
        .{ .name = "a", .schema = integer },
    });
    const operation = try author.local("named operation", left.schema, integer, .linear);
    var relabeled = operation;
    relabeled.payload = right.schema;
    try std.testing.expectError(error.TypeMismatch, author.interpret(.{
        .operation = relabeled,
        .input = integer,
        .answer = integer,
        .mode = .deep,
        .use = .linear,
    }));
}

test "finished blocks reject named result relabeling" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const left = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const right = try author.record(&.{
        .{ .name = "b", .schema = integer },
        .{ .name = "a", .schema = integer },
    });
    const function = try author.declare("block origin", &.{}, right.schema, &.{});
    var body = try author.body(function);
    const value = try body.product(left, &.{
        .{ .name = "a", .value = try author.literal(u64, 1) },
        .{ .name = "b", .value = try author.literal(u64, 2) },
    });
    var block = try body.finish(value);
    block.result = right.schema;
    try std.testing.expectError(error.TypeMismatch, author.define(function, block));
}

test "interpretations reject named answer relabeling" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const left = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const right = try author.record(&.{
        .{ .name = "b", .schema = integer },
        .{ .name = "a", .schema = integer },
    });
    const operation = try author.local("answer operation", integer, integer, .linear);
    const interpretation = try author.interpret(.{ .operation = operation, .input = left.schema, .answer = left.schema, .mode = .deep, .use = .linear });
    const capability = try author.capability(operation);
    const work = try author.declare("answer work", &.{.{ .name = "capability", .schema = capability }}, left.schema, &.{operation});
    var body = try author.ambient("answer caller");
    const callable = try body.lambda(work, &.{}, .reusable);
    var relabeled = interpretation;
    relabeled.answer = right.schema;
    try std.testing.expectError(error.TypeMismatch, body.handle(relabeled, callable, &.{}, &.{}));
}

test "module failure layout follows defined authored failures" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const left = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const right = try author.record(&.{
        .{ .name = "b", .schema = integer },
        .{ .name = "a", .schema = integer },
    });
    const entry = try author.declare("failure entry", &.{}, integer, &.{});
    var body = try author.body(entry);
    const failure = try body.product(left, &.{
        .{ .name = "a", .value = try author.literal(u64, 1) },
        .{ .name = "b", .value = try author.literal(u64, 2) },
    });
    try author.define(entry, try body.fail(failure, integer));
    try std.testing.expectError(error.TypeMismatch, author.module(entry, right.schema));
    try std.testing.expectEqual(a.Category.schema_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("failure value", author.diagnostic.?.entity);

    var unused = try author.ambient("unused failure");
    const unrelated = try unused.product(right, &.{
        .{ .name = "b", .value = try author.literal(u64, 3) },
        .{ .name = "a", .value = try author.literal(u64, 4) },
    });
    _ = try unused.fail(unrelated, integer);
    _ = try author.module(entry, left.schema);
}

test "module failure layout reaches authored cleanup exits" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const left = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const right = try author.record(&.{
        .{ .name = "b", .schema = integer },
        .{ .name = "a", .schema = integer },
    });
    const work = try author.declare("cleanup work", &.{}, integer, &.{});
    var work_body = try author.body(work);
    try author.define(work, try work_body.finish(try author.literal(u64, 7)));
    const cleanup = try author.declare("cleanup exit", &.{.{ .name = "exit", .schema = try author.exitInfo(left.schema) }}, unit, &.{});
    var cleanup_body = try author.body(cleanup);
    try author.define(cleanup, try cleanup_body.finish(try author.literal(void, {})));
    const entry = try author.declare("cleanup entry", &.{}, integer, &.{});
    var body = try author.body(entry);
    const protected = try body.protect(try body.lambda(work, &.{}, .reusable), try body.lambda(cleanup, &.{}, .reusable), &.{}, null, null);
    try author.define(entry, try body.finish(protected));
    try std.testing.expectError(error.TypeMismatch, author.module(entry, right.schema));
    try std.testing.expectEqualStrings("cleanup exit failure", author.diagnostic.?.entity);
    _ = try author.module(entry, left.schema);
}

test "protected cleanup requires an authored exit-info parameter and unit result" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const failure = try author.record(&.{.{ .name = "reason", .schema = integer }});
    const work = try author.declare("cleanup check work", &.{}, integer, &.{});
    var work_body = try author.body(work);
    try author.define(work, try work_body.finish(try author.literal(u64, 7)));
    var body = try author.ambient("cleanup checks");
    const work_callable = try body.lambda(work, &.{}, .reusable);

    const wrong_input = try author.declare("wrong exit input", &.{.{ .name = "exit", .schema = integer }}, unit, &.{});
    var wrong_input_body = try author.body(wrong_input);
    try author.define(wrong_input, try wrong_input_body.finish(try author.literal(void, {})));
    try std.testing.expectError(error.TypeMismatch, body.protect(work_callable, try body.lambda(wrong_input, &.{}, .reusable), &.{}, null, null));
    try std.testing.expectEqualStrings("cleanup exit parameter", author.diagnostic.?.entity);

    const exit_info = try author.exitInfo(failure.schema);
    const wrong_output = try author.declare("wrong cleanup result", &.{.{ .name = "exit", .schema = exit_info }}, integer, &.{});
    var wrong_output_body = try author.body(wrong_output);
    try author.define(wrong_output, try wrong_output_body.finish(try author.literal(u64, 1)));
    try std.testing.expectError(error.TypeMismatch, body.protect(work_callable, try body.lambda(wrong_output, &.{}, .reusable), &.{}, null, null));
    try std.testing.expectEqualStrings("cleanup result", author.diagnostic.?.entity);

    const raw_exit = try author.adoptSchema(exit_info.id);
    const adopted = try author.declare("adopted exit", &.{.{ .name = "exit", .schema = raw_exit }}, unit, &.{});
    var adopted_body = try author.body(adopted);
    try author.define(adopted, try adopted_body.finish(try author.literal(void, {})));
    try std.testing.expectError(error.TypeMismatch, body.protect(work_callable, try body.lambda(adopted, &.{}, .reusable), &.{}, null, null));
    try std.testing.expectEqualStrings("cleanup exit parameter", author.diagnostic.?.entity);
}

test "module rejects a raw protection term missing named cleanup provenance" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const failure = try author.record(&.{.{ .name = "reason", .schema = integer }});
    const work = try author.declare("raw protect work", &.{}, integer, &.{});
    var work_body = try author.body(work);
    try author.define(work, try work_body.finish(try author.literal(u64, 7)));
    const raw_exit = try author.adoptSchema((try author.exitInfo(failure.schema)).id);
    const cleanup = try author.declare("raw protect cleanup", &.{.{ .name = "exit", .schema = raw_exit }}, unit, &.{});
    var cleanup_body = try author.body(cleanup);
    try author.define(cleanup, try cleanup_body.finish(try author.literal(void, {})));
    var staging = try author.ambient("raw protection staging");
    const work_callable = try staging.lambda(work, &.{}, .reusable);
    const cleanup_callable = try staging.lambda(cleanup, &.{}, .reusable);
    const entry = try author.declare("raw protection entry", &.{}, integer, &.{});
    try raw.define(entry.id, try raw.term(.{ .protect = .{
        .body = work_callable.value.id,
        .cleanup = cleanup_callable.value.id,
    } }));
    try std.testing.expectError(error.TypeMismatch, author.module(entry, failure.schema));
    try std.testing.expectEqualStrings("cleanup exit failure", author.diagnostic.?.entity);
}

test "named module failure rejects a raw fail value without provenance" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const first = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const renamed = try author.record(&.{
        .{ .name = "b", .schema = integer },
        .{ .name = "a", .schema = integer },
    });
    const entry = try author.declare("raw fail entry", &.{}, integer, &.{});
    const raw_value = try raw.primitive(first.schema.id, .product, &.{ try raw.constant(u64, 1), try raw.constant(u64, 2) }, 0);
    try raw.define(entry.id, try raw.term(.{ .fail = raw_value }));
    try std.testing.expectError(error.TypeMismatch, author.module(entry, renamed.schema));
    try std.testing.expectEqualStrings("failure value", author.diagnostic.?.entity);
    try std.testing.expectEqualStrings("missing raw failure provenance", author.diagnostic.?.relationship.?);
}

test "named module failure rejects a raw cleanup lambda without provenance" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const failure = try author.record(&.{.{ .name = "reason", .schema = integer }});
    const work = try author.declare("raw cleanup work", &.{}, integer, &.{});
    var work_body = try author.body(work);
    try author.define(work, try work_body.finish(try author.literal(u64, 7)));
    const cleanup = try author.declare("raw cleanup", &.{.{ .name = "exit", .schema = try author.exitInfo(failure.schema) }}, unit, &.{});
    var cleanup_body = try author.body(cleanup);
    try author.define(cleanup, try cleanup_body.finish(try author.literal(void, {})));
    var staging = try author.ambient("raw cleanup staging");
    const work_callable = try staging.lambda(work, &.{}, .reusable);
    const cleanup_schema = try author.callableSchema(cleanup, &.{}, .reusable);
    const raw_cleanup = try raw.lambda(cleanup.id, cleanup_schema.id);
    const entry = try author.declare("raw cleanup entry", &.{}, integer, &.{});
    try raw.define(entry.id, try raw.term(.{ .protect = .{
        .body = work_callable.value.id,
        .cleanup = raw_cleanup,
    } }));
    try std.testing.expectError(error.TypeMismatch, author.module(entry, failure.schema));
    try std.testing.expectEqualStrings("cleanup exit failure", author.diagnostic.?.entity);
    try std.testing.expectEqualStrings("missing raw cleanup provenance", author.diagnostic.?.relationship.?);
}

test "checked addition uses a distinct literal failure handle" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const literal = try author.literalFailure(void, {});
    try std.testing.expect(@TypeOf(literal) != a.Value);
    const entry = try author.declare("checked addition entry", &.{}, integer, &.{});
    var body = try author.body(entry);
    const sum = try body.checkedAdd(try author.literal(u64, 1), try author.literal(u64, 2), literal);
    try author.define(entry, try body.finish(sum));
    _ = try author.module(entry, unit);
}

test "named module failure checks reachable checked-add literal provenance" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const failure = try author.record(&.{.{ .name = "reason", .schema = integer }});
    const entry = try author.declare("checked failure entry", &.{}, integer, &.{});
    var body = try author.body(entry);
    const sum = try body.checkedAdd(try author.literal(u64, 1), try author.literal(u64, 2), try author.literalFailure(void, {}));
    try author.define(entry, try body.finish(sum));
    try std.testing.expectError(error.TypeMismatch, author.module(entry, failure.schema));
    try std.testing.expectEqualStrings("checked failure literal", author.diagnostic.?.entity);
}

test "named module failure rejects a raw primitive failure without provenance" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const failure = try author.record(&.{.{ .name = "reason", .schema = integer }});
    const entry = try author.declare("raw primitive failure", &.{}, integer, &.{});
    const bytes = [_]u8{0} ** 8;
    const raw_literal = try raw.literal(.{ .schema = failure.schema.id, .bytes = &bytes });
    const fault = try raw.failureLiteral(raw_literal);
    const sum = try raw.value(.{ .schema = integer.id, .expression = .{ .primitive = .{
        .opcode = .integer_add,
        .operands = &.{ try raw.constant(u64, 1), try raw.constant(u64, 2) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = fault }},
    } } });
    try raw.define(entry.id, try raw.pure(sum));
    try std.testing.expectError(error.TypeMismatch, author.module(entry, failure.schema));
    try std.testing.expectEqualStrings("missing primitive failure provenance", author.diagnostic.?.relationship.?);
}

test "compile rechecks the issued module after a later helper definition" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const left = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const right = try author.record(&.{
        .{ .name = "b", .schema = integer },
        .{ .name = "a", .schema = integer },
    });
    const entry = try author.declare("published entry", &.{}, integer, &.{});
    var entry_body = try author.body(entry);
    try author.define(entry, try entry_body.finish(try author.literal(u64, 7)));
    const helper = try author.declare("late helper", &.{}, integer, &.{});
    var helper_body = try author.body(helper);
    const failed = try helper_body.product(right, &.{
        .{ .name = "b", .value = try author.literal(u64, 1) },
        .{ .name = "a", .value = try author.literal(u64, 2) },
    });
    const helper_block = try helper_body.fail(failed, integer);
    const left_module = try author.module(entry, left.schema);
    const right_module = try author.module(entry, right.schema);
    for (0..100) |_| {
        const unrelated = try author.declare("unrelated", &.{}, integer, &.{});
        var unrelated_body = try author.body(unrelated);
        try author.define(unrelated, try unrelated_body.finish(try author.literal(u64, 0)));
    }
    try author.define(helper, helper_block);
    try std.testing.expectError(error.TypeMismatch, author.compile(std.testing.allocator, left_module));
    try std.testing.expectEqualStrings("failure value", author.diagnostic.?.entity);
    var compiled = try author.compile(std.testing.allocator, right_module);
    compiled.deinit();
}

test "protected work accepts an adopted borrowed schema with its source region" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const owned = try author.resource(integer);
    const loan = author.region();
    const other_loan = author.region();
    const borrowed = try author.borrowedSchema(owned, loan);
    const raw_owned = try author.adoptSchema(owned.id);
    const raw_borrowed = try author.adoptSchema(borrowed.id);
    const work = try author.declareScoped("adopted borrowed work", &.{.{ .name = "borrowed", .schema = raw_borrowed }}, integer, &.{}, &.{loan});
    var work_body = try author.body(work);
    try author.define(work, try work_body.finish(try author.literal(u64, 7)));
    const cleanup = try author.declare("adopted owned cleanup", &.{
        .{ .name = "exit", .schema = try author.exitInfo(unit) },
        .{ .name = "owned", .schema = raw_owned },
    }, unit, &.{});
    var cleanup_body = try author.body(cleanup);
    try author.define(cleanup, try cleanup_body.finish(try author.literal(void, {})));
    var body = try author.ambient("adopted borrow");
    const resource_value = try body.packResource(raw_owned, try author.literal(u64, 9));
    const work_callable = try body.lambda(work, &.{}, .reusable);
    const cleanup_callable = try body.lambda(cleanup, &.{}, .reusable);
    _ = try body.protect(work_callable, cleanup_callable, &.{}, resource_value, loan);
    try std.testing.expectError(error.TypeMismatch, body.protect(work_callable, cleanup_callable, &.{}, resource_value, other_loan));
}

test "select and named aggregates report source-oriented diagnostics" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const boolean = try author.scalar(bool);
    var body = try author.ambient("diagnostic joins");
    var yes = try body.child("yes");
    var no = try body.child("no");
    const yes_block = try yes.finish(try author.literal(u64, 1));
    const no_block = try no.finish(try author.literal(u64, 2));
    try std.testing.expectError(error.TypeMismatch, body.select(try author.literal(u64, 1), yes_block, no_block));
    try std.testing.expectEqual(a.Category.schema_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("conditional condition", author.diagnostic.?.entity);
    var copied = try a.OwnedDiagnostic.copy(std.testing.allocator, author.diagnostic.?);
    defer copied.deinit();

    const record = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const one = try author.literal(u64, 1);
    try std.testing.expectError(error.DuplicateName, body.product(record, &.{
        .{ .name = "a", .value = one },
        .{ .name = "a", .value = one },
    }));
    try std.testing.expectEqual(a.Category.field_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("duplicate named field", author.diagnostic.?.relationship.?);
    try std.testing.expectError(error.InvalidField, body.product(record, &.{
        .{ .name = "a", .value = one },
        .{ .name = "other", .value = one },
    }));
    try std.testing.expectEqualStrings("b", author.diagnostic.?.entity);
    try std.testing.expectEqualStrings("missing named field", author.diagnostic.?.relationship.?);

    const variant = try author.variant(&.{
        .{ .name = "left", .schema = integer },
        .{ .name = "right", .schema = integer },
    });
    const tagged = try body.inject(variant, "left", one);
    var left_case = try body.variantCase(variant, "left");
    const left_branch = try left_case.finish(try author.literal(u64, 1));
    var right_case = try body.variantCase(variant, "right");
    const right_branch = try right_case.finish(try author.literal(bool, true));
    try std.testing.expectError(error.TypeMismatch, body.matchVariant(variant, tagged, &.{ left_branch, right_branch }));
    try std.testing.expectEqual(a.Category.branch_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("variant branch result", author.diagnostic.?.entity);
    try std.testing.expectEqual(integer.id, author.diagnostic.?.expected.?);
    try std.testing.expectEqual(boolean.id, author.diagnostic.?.actual.?);
}

test "schema comparison visits shared named metadata as a graph" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const named = try author.record(&.{.{ .name = "left", .schema = integer }});
    const renamed = try author.record(&.{.{ .name = "right", .schema = integer }});
    var left = named.schema;
    var equivalent = named.schema;
    var different = renamed.schema;
    for (0..28) |_| {
        left = try author.productSchema(&.{ left, left });
        equivalent = try author.productSchema(&.{ equivalent, equivalent });
        different = try author.productSchema(&.{ different, different });
    }
    const consumer = try author.declare("consume graph", &.{.{ .name = "value", .schema = left }}, integer, &.{});
    const rejected = try author.declare("reject graph", &.{.{ .name = "value", .schema = different }}, integer, &.{});
    const producer = try author.declare("produce graph", &.{.{ .name = "value", .schema = equivalent }}, integer, &.{});
    var body = try author.body(producer);
    const value = try body.parameter("value");
    _ = try body.call(consumer, &.{value});
    try std.testing.expectError(error.TypeMismatch, body.call(rejected, &.{value}));
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
    const sum = try body.checkedAdd(try body.field(record, directly, "left"), try body.field(record, applied, "right"), try author.literalFailure(void, {}));
    try author.define(entry, try body.finish(sum));
    var compiled = try author.compile(std.testing.allocator, try author.module(entry, try author.scalar(void)));
    compiled.deinit();
}

test "structural product sum and sequence schemas retain named children" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const left = try author.record(&.{.{ .name = "left", .schema = integer }});
    const right = try author.record(&.{.{ .name = "right", .schema = integer }});
    const sequence_left = try author.sequenceSchema(left.schema);
    const sequence_right = try author.sequenceSchema(right.schema);
    try std.testing.expectEqual(sequence_left.id, sequence_right.id);
    const identity = try author.declare("sequence identity", &.{
        .{ .name = "items", .schema = sequence_left },
    }, sequence_left, &.{});
    var identity_body = try author.body(identity);
    try author.define(identity, try identity_body.finish(try identity_body.parameter("items")));
    const entry = try author.declare("entry", &.{
        .{ .name = "items", .schema = sequence_left },
    }, sequence_left, &.{});
    var entry_body = try author.body(entry);
    const returned = try entry_body.call(identity, &.{try entry_body.parameter("items")});
    try author.define(entry, try entry_body.finish(returned));
    var compiled = try author.compile(std.testing.allocator, try author.module(entry, unit));
    compiled.deinit();

    var body = try author.ambient("nested layouts");
    const left_value = try body.product(left, &.{
        .{ .name = "left", .value = try author.literal(u64, 11) },
    });
    const right_value = try body.product(right, &.{
        .{ .name = "right", .value = try author.literal(u64, 22) },
    });
    const left_items = try body.singletonSequence(left_value);
    const right_items = try body.singletonSequence(right_value);
    try std.testing.expectError(error.TypeMismatch, body.concatSequences(left_items, right_items));
    const receives_right = try author.declare("right sequence", &.{
        .{ .name = "items", .schema = sequence_right },
    }, unit, &.{});
    try std.testing.expectError(error.TypeMismatch, body.call(receives_right, &.{left_items}));
    const lookup = try author.external("sequence/lookup", sequence_right, unit);
    try std.testing.expectError(error.TypeMismatch, body.perform(lookup, left_items));
    try std.testing.expectEqual(a.Category.schema_mismatch, author.diagnostic.?.category);

    const product_left = try author.productSchema(&.{left.schema});
    const product_right = try author.productSchema(&.{right.schema});
    const sum_left = try author.sumSchema(&.{left.schema});
    const sum_right = try author.sumSchema(&.{right.schema});
    try std.testing.expectEqual(product_left.id, product_right.id);
    try std.testing.expectEqual(sum_left.id, sum_right.id);
    const wrong_product = try author.declare("wrong product", &.{
        .{ .name = "value", .schema = product_right },
    }, unit, &.{});
    const wrong_sum = try author.declare("wrong sum", &.{
        .{ .name = "value", .schema = sum_right },
    }, unit, &.{});
    const product_entry = try author.declare("product source", &.{
        .{ .name = "value", .schema = product_left },
    }, unit, &.{});
    const sum_entry = try author.declare("sum source", &.{
        .{ .name = "value", .schema = sum_left },
    }, unit, &.{});
    var product_body = try author.body(product_entry);
    var sum_body = try author.body(sum_entry);
    try std.testing.expectError(error.TypeMismatch, product_body.call(wrong_product, &.{try product_body.parameter("value")}));
    try std.testing.expectError(error.TypeMismatch, sum_body.call(wrong_sum, &.{try sum_body.parameter("value")}));
    const region = author.region();
    const cell_left = try author.cellSchema(region, left.schema);
    const cell_right = try author.cellSchema(region, right.schema);
    const exit_left = try author.exitInfo(left.schema);
    const exit_right = try author.exitInfo(right.schema);
    try std.testing.expectEqual(cell_left.id, cell_right.id);
    try std.testing.expectEqual(exit_left.id, exit_right.id);
    const wrong_cell = try author.declare("wrong cell", &.{
        .{ .name = "value", .schema = cell_right },
    }, unit, &.{});
    const wrong_exit = try author.declare("wrong exit", &.{
        .{ .name = "value", .schema = exit_right },
    }, unit, &.{});
    const cell_source = try author.declare("cell source", &.{
        .{ .name = "value", .schema = cell_left },
    }, unit, &.{});
    const exit_source = try author.declare("exit source", &.{
        .{ .name = "value", .schema = exit_left },
    }, unit, &.{});
    var cell_body = try author.body(cell_source);
    var exit_body = try author.body(exit_source);
    try std.testing.expectError(error.TypeMismatch, cell_body.call(wrong_cell, &.{try cell_body.parameter("value")}));
    try std.testing.expectError(error.TypeMismatch, exit_body.call(wrong_exit, &.{try exit_body.parameter("value")}));
}

test "raw interop cannot relabel an exported named value or term" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const left = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const right = try author.record(&.{
        .{ .name = "b", .schema = integer },
        .{ .name = "a", .schema = integer },
    });
    var body = try author.ambient("interop");
    const value = try body.product(left, &.{
        .{ .name = "a", .value = try author.literal(u64, 11) },
        .{ .name = "b", .value = try author.literal(u64, 22) },
    });
    const raw_id = try a.Interop.rawValue(&body, value);
    try std.testing.expectError(error.TypeMismatch, a.Interop.adoptValue(&body, raw_id, right.schema));
    _ = try a.Interop.adoptValue(&body, raw_id, left.schema);
    const unknown = try raw.primitive(left.schema.id, .product, &.{
        try raw.constant(u64, 1), try raw.constant(u64, 2),
    }, 0);
    try std.testing.expectError(error.InvalidSource, a.Interop.adoptValue(&body, unknown, left.schema));
    var child = try body.child("term");
    const local = try child.checkedAdd(try author.literal(u64, 1), try author.literal(u64, 2), try author.literalFailure(void, {}));
    const local_id = try a.Interop.rawValue(&child, local);
    try std.testing.expectError(error.OutOfScope, a.Interop.adoptValue(&body, local_id, integer));
    _ = try a.Interop.adoptValue(&child, local_id, integer);
    const term = try a.Interop.rawTerm(try child.finish(value));
    try std.testing.expectError(error.TypeMismatch, a.Interop.term(&body, term, right.schema));
    try std.testing.expectError(error.OutOfScope, a.Interop.term(&body, term, left.schema));
}

test "metadata-free raw callable cannot satisfy a named handler result" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const first = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const renamed = try author.record(&.{
        .{ .name = "b", .schema = integer },
        .{ .name = "a", .schema = integer },
    });
    const operation = try author.local("raw/handler", integer, integer, .linear);
    const interpretation = try author.interpret(.{ .operation = operation, .input = first.schema, .answer = first.schema, .mode = .deep, .use = .linear });
    const capability = try author.capability(operation);
    const work = try author.declare("raw handled work", &.{.{ .name = "capability", .schema = capability }}, renamed.schema, &.{operation});
    const raw_callable_id = try raw.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{capability.id},
        .result = renamed.schema.id,
        .effects = &.{operation.id},
        .use = .reusable,
    } } });
    var body = try author.ambient("raw handler caller");
    const raw_value = try a.Interop.adoptValue(&body, try raw.lambda(work.id, raw_callable_id), try author.adoptSchema(raw_callable_id));
    try std.testing.expectError(error.TypeMismatch, body.handle(interpretation, try body.asCallable(raw_value), &.{}, &.{}));
    try std.testing.expectEqualStrings("handled body result", author.diagnostic.?.entity);
}

test "metadata-free raw resumption cannot accept a named reply alias" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const first = try author.record(&.{
        .{ .name = "a", .schema = integer },
        .{ .name = "b", .schema = integer },
    });
    const renamed = try author.record(&.{
        .{ .name = "b", .schema = integer },
        .{ .name = "a", .schema = integer },
    });
    const operation = try author.local("raw/resumption", integer, first.schema, .linear);
    const interpretation = try author.interpret(.{ .operation = operation, .input = first.schema, .answer = first.schema, .mode = .deep, .use = .linear });
    var clause = try author.body(interpretation.clause);
    const variable = raw.parameter(interpretation.clause.id, interpretation.clause.parameters.len - 1);
    const raw_schema = try author.adoptSchema(interpretation.resumption.id);
    const raw_token = try a.Interop.adoptValue(&clause, try raw.reference(variable), raw_schema);
    const renamed_value = try clause.product(renamed, &.{
        .{ .name = "b", .value = try author.literal(u64, 1) },
        .{ .name = "a", .value = try author.literal(u64, 2) },
    });
    try std.testing.expectError(error.TypeMismatch, clause.resumeValue(raw_token, renamed_value));
    try std.testing.expectEqualStrings("resumption input", author.diagnostic.?.entity);
    const valid = try clause.product(first, &.{
        .{ .name = "a", .value = try author.literal(u64, 3) },
        .{ .name = "b", .value = try author.literal(u64, 4) },
    });
    try std.testing.expectError(error.TypeMismatch, clause.resumeValue(raw_token, valid));
    _ = try clause.resumeValue(try clause.parameter("resume"), valid);
}

test "raw interop rejects malformed nested schema references before indexing" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    var body = try author.ambient("malformed interop");

    const resumption_id = try raw.schema(.{ .internal = .{ .resumption = .{
        .effect = 999,
        .input = integer.id,
        .answer = integer.id,
        .handled = &.{},
        .mode = .deep,
        .use = .linear,
    } } });
    const work_id = try raw.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = integer.id,
    } } });
    const resumption = try a.Interop.adoptValue(&body, try raw.reference(try raw.variable(resumption_id)), try author.adoptSchema(resumption_id));
    const work = try a.Interop.adoptValue(&body, try raw.reference(try raw.variable(work_id)), try author.adoptSchema(work_id));
    try std.testing.expectError(error.InvalidReference, body.resumeComputation(resumption, try body.asCallable(work)));
    try std.testing.expectEqual(a.Category.capability_mismatch, author.diagnostic.?.category);

    const operation = try author.local("malformed/operation", integer, integer, .linear);
    const handler = try author.interpret(.{ .operation = operation, .input = integer, .answer = integer, .mode = .deep, .use = .linear });
    const invalid_callable_id = try raw.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{999},
        .result = integer.id,
    } } });
    const invalid_callable = try a.Interop.adoptValue(&body, try raw.reference(try raw.variable(invalid_callable_id)), try author.adoptSchema(invalid_callable_id));
    try std.testing.expectError(error.InvalidSchema, body.handle(handler, try body.asCallable(invalid_callable), &.{}, &.{}));
    try std.testing.expectEqual(a.Category.schema_mismatch, author.diagnostic.?.category);
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
    const without_cap = try author.declare("without capability", &.{}, integer, &.{});
    try std.testing.expectError(error.InvalidArgument, clause.handle(interpretation, try clause.lambda(without_cap, &.{}, .reusable), &.{}, &.{}));
    try std.testing.expectEqual(a.Category.argument_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("handled body capability", author.diagnostic.?.entity);
    _ = author.region();
    try std.testing.expect(author.diagnostic == null);
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

test "local and scoped payload mismatches report the failed schema relation" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const local = try author.local("local", integer, unit, .linear);
    const scoped = try author.scopedLocal("scoped", integer, unit, &.{}, &.{}, .linear);
    const local_cap = try author.capability(local);
    const scoped_cap = try author.capability(scoped);
    const entry = try author.declare("entry", &.{
        .{ .name = "local", .schema = local_cap },
        .{ .name = "scoped", .schema = scoped_cap },
    }, unit, &.{ local, scoped });
    var body = try author.body(entry);
    const wrong = try author.literal(bool, false);
    try std.testing.expectError(error.TypeMismatch, body.performLocal(local, try body.parameter("local"), wrong));
    try std.testing.expectEqual(a.Category.schema_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("local operation payload", author.diagnostic.?.entity);
    try std.testing.expectError(error.TypeMismatch, body.performScoped(scoped, try body.parameter("scoped"), wrong, &.{}, &.{}));
    try std.testing.expectEqual(a.Category.schema_mismatch, author.diagnostic.?.category);
    try std.testing.expectEqualStrings("scoped operation payload", author.diagnostic.?.entity);
}

test "handler name collision rejects before declaring either function" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const unit = try author.scalar(void);
    const question = try author.local("name collision", unit, integer, .affine);
    const initial_count = raw.functions.items.len;
    for ([_][]const u8{ "value", "payload", "resume" }) |name| {
        try std.testing.expectError(error.DuplicateName, author.interpret(.{
            .operation = question,
            .input = integer,
            .answer = integer,
            .mode = .deep,
            .use = .affine,
            .state = &.{.{ .name = name, .schema = integer }},
        }));
        try std.testing.expectEqual(initial_count, raw.functions.items.len);
    }
    const valid = try author.interpret(.{
        .operation = question,
        .input = integer,
        .answer = integer,
        .mode = .deep,
        .use = .affine,
        .state = &.{.{ .name = "phase", .schema = integer }},
    });
    var returns = try author.body(valid.returns);
    try author.define(valid.returns, try returns.finish(try returns.parameter("value")));
    var clause = try author.body(valid.clause);
    try author.define(valid.clause, try clause.finish(try author.literal(u64, 7)));
    const entry = try author.declare("entry", &.{}, integer, &.{});
    var body = try author.body(entry);
    try author.define(entry, try body.finish(try author.literal(u64, 1)));
    var compiled = try author.compile(std.testing.allocator, try author.module(entry, unit));
    compiled.deinit();
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
    try std.testing.expectEqualStrings("missing", author.diagnostic.?.entity);
    try std.testing.expectEqualStrings("named function parameter", author.diagnostic.?.relationship.?);
    raw.deinit();
    alive = false;
    try std.testing.expectEqual(a.Category.argument_mismatch, owned.detail.category);
    try std.testing.expectEqualStrings("expects integer", owned.detail.entity);
    var text: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer text.deinit();
    try owned.detail.render(&text.writer);
    try std.testing.expect(std.mem.indexOf(u8, text.written(), "argument_mismatch") != null);
}

test "diagnostic field names survive caller buffer mutation" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var author = a.Builder.init(&raw);
    const integer = try author.scalar(u64);
    const record = try author.record(&.{.{ .name = "value", .schema = integer }});
    var body = try author.ambient("diagnostic names");
    const product = try body.product(record, &.{
        .{ .name = "value", .value = try author.literal(u64, 7) },
    });
    var field_name = [_]u8{ 'm', 'i', 's', 's' };
    try std.testing.expectError(error.InvalidField, body.field(record, product, &field_name));
    field_name[0] = 'x';
    try std.testing.expectEqualStrings("miss", author.diagnostic.?.entity);
    var snapshot = try a.OwnedDiagnostic.copy(std.testing.allocator, author.diagnostic.?);
    defer snapshot.deinit();
    const variant = try author.variant(&.{.{ .name = "left", .schema = integer }});
    var tag_name = [_]u8{ 'l', 'e', 'f', 't' };
    try std.testing.expectError(error.TypeMismatch, body.inject(variant, &tag_name, try author.literal(bool, false)));
    tag_name[0] = 'x';
    try std.testing.expectEqualStrings("left", author.diagnostic.?.entity);
    try std.testing.expectEqualStrings("miss", snapshot.detail.entity);
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

test "resource, parameter, child, and variant allocation failures poison publication" {
    const Mode = enum { resource, parameter, child, variant_case };
    const Pressure = struct {
        fn run(author: *a.Builder, body: *a.Body, variant: a.Variant, integer: a.Schema, mode: Mode) a.Error!void {
            switch (mode) {
                .resource => _ = try author.resource(integer),
                .parameter => _ = try body.parameter("x"),
                .child => _ = try body.child("fresh child"),
                .variant_case => _ = try body.variantCase(variant, "value"),
            }
        }
    };
    for ([_]Mode{
        .resource, .parameter, .child, .variant_case,
    }) |mode| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var raw = source.Builder.init(failing.allocator());
        var author = a.Builder.init(&raw);
        const integer = try author.scalar(u64);
        const unit = try author.scalar(void);
        const entry = try author.declare("entry", &.{}, integer, &.{});
        var entry_body = try author.body(entry);
        try author.define(entry, try entry_body.finish(try author.literal(u64, 1)));
        const helper = try author.declare("helper", &.{
            .{ .name = "x", .schema = integer },
        }, integer, &.{});
        var body = try author.body(helper);
        const variant = try author.variant(&.{.{ .name = "value", .schema = integer }});
        failing.fail_index = failing.alloc_index;
        failing.resize_fail_index = failing.resize_index;
        var exhausted = false;
        for (0..10_000) |_| {
            Pressure.run(&author, &body, variant, integer, mode) catch |err| {
                try std.testing.expectEqual(error.OutOfMemory, err);
                exhausted = true;
                break;
            };
        }
        try std.testing.expect(exhausted);
        try std.testing.expect(author.poisoned);
        try std.testing.expectError(error.InvalidSource, author.module(entry, unit));
        raw.deinit();
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}
