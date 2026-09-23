const std = @import("std");
const author = @import("author.zig");
const source = @import("source.zig");

test "structured branches emit one selected external operation" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var a = try author.Session.init(&raw);
    defer a.deinit();
    const boolean = try a.scalar(bool);
    const integer = try a.scalar(u32);
    const unit = try a.scalar(void);
    const left = try a.external("author.left", integer, integer);
    const right = try a.external("author.right", integer, integer);
    const entry = try a.declare(&.{
        .{ .name = "select_left", .schema = boolean },
        .{ .name = "payload", .schema = integer },
    }, integer, &.{ left, right });
    var body = try a.body(entry);
    const selected = try body.parameter("select_left");
    const payload = try body.parameter("payload");
    var when_true = try body.child();
    const left_result = try when_true.bind(try when_true.perform(left, payload));
    const left_body = try when_true.finish(left_result);
    var when_false = try body.child();
    try std.testing.expectError(error.OutOfScope, when_false.perform(right, left_result));
    try std.testing.expectEqual(author.Category.out_of_scope, a.diagnostic.?.category);
    const right_result = try when_false.bind(try when_false.perform(right, payload));
    const right_body = try when_false.finish(right_result);
    const answer = try body.bind(try body.conditional(selected, left_body, right_body));
    try body.finishFunction(answer);
    var compiled = try source.lower(std.testing.allocator, try a.module(entry, unit));
    defer compiled.deinit();
    try std.testing.expectEqual(@as(usize, 2), raw.effects.items.len);
}

test "equal numeric indices from live builders do not confer origin" {
    var first = source.Builder.init(std.testing.allocator);
    defer first.deinit();
    var second = source.Builder.init(std.testing.allocator);
    defer second.deinit();
    var a = try author.Session.init(&first);
    defer a.deinit();
    var b = try author.Session.init(&second);
    defer b.deinit();
    const one = try a.scalar(u32);
    const two = try b.scalar(u32);
    try std.testing.expectEqual(one.id, two.id);
    const operation = try b.external("builder.two", two, two);
    const entry = try b.declare(&.{}, two, &.{operation});
    var body = try b.body(entry);
    var alien_body = try a.body(try a.declare(&.{}, one, &.{}));
    const alien = try alien_body.constant(u32, 3);
    try std.testing.expectError(error.WrongBuilder, body.perform(operation, alien));
    try std.testing.expectEqual(author.Category.wrong_builder, b.diagnostic.?.category);
}

test "nested authoring closure captures its parent and named dynamic fields check" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var a = try author.Session.init(&raw);
    defer a.deinit();
    const integer = try a.scalar(u32);
    const boolean = try a.scalar(bool);
    const unit = try a.scalar(void);
    const record = try a.record(&.{
        .{ .name = "number", .schema = integer },
        .{ .name = "flag", .schema = boolean },
    });
    const outer = try a.declare(&.{.{ .name = "x", .schema = integer }}, integer, &.{});
    var body = try a.body(outer);
    const x = try body.parameter("x");
    const nested = try body.declare(&.{}, integer, &.{});
    var nested_body = try a.body(nested);
    try nested_body.finishFunction(x);
    const called = try body.bind(try body.call(nested, &.{}));
    const pair = try body.makeRecord(record, &.{
        .{ .name = "flag", .value = try body.constant(bool, true) },
        .{ .name = "number", .value = called },
    });
    const field = try body.field(record, pair, "number");
    try body.finishFunction(field);
    var compiled = try source.lower(std.testing.allocator, try a.module(outer, unit));
    defer compiled.deinit();
}

test "derived local interpretation changes answer and rejects a different instance" {
    var raw = source.Builder.init(std.testing.allocator);
    defer raw.deinit();
    var a = try author.Session.init(&raw);
    defer a.deinit();
    const unit = try a.scalar(void);
    const boolean = try a.scalar(bool);
    const integer = try a.scalar(u32);
    const left = try a.local("same-name", unit, boolean, .linear);
    const right = try a.local("same-name", unit, boolean, .linear);
    const handler = try a.interpret(left, .{
        .mode = .deep,
        .input = boolean,
        .answer = integer,
        .resumption_use = .linear,
        .capture_bound = &.{ unit, boolean, integer, left.capability.? },
    });
    var returns = try a.body(handler.on_return);
    try returns.finishFunction(try returns.constant(u32, 7));
    var clause = try a.body(handler.on_operation);
    const token = try clause.parameter("resume");
    const resumed = try clause.bind(try clause.resumeValue(token, try clause.constant(bool, true)));
    try clause.finishFunction(resumed);
    const body_fn = try a.declare(&.{.{ .name = "cap", .schema = left.capability.? }}, boolean, &.{left});
    var operation_body = try a.body(body_fn);
    const cap = try operation_body.parameter("cap");
    const payload = try operation_body.constant(void, {});
    try std.testing.expectError(error.InvalidOperation, operation_body.performLocal(right, cap, payload));
    const answer = try operation_body.bind(try operation_body.performLocal(left, cap, payload));
    try operation_body.finishFunction(answer);
    const callable = try a.dynamicSchema(.{ .internal = .{ .computation = .{
        .parameters = &.{left.capability.?.id},
        .result = boolean.id,
        .effects = &.{left.id},
        .use = .linear,
    } } });
    const entry = try a.declare(&.{}, integer, &.{});
    var main = try a.body(entry);
    const installed = try main.bind(try main.handle(handler, try main.lambda(body_fn, callable), &.{}, &.{}));
    try main.finishFunction(installed);
    var compiled = try source.lower(std.testing.allocator, try a.module(entry, unit));
    defer compiled.deinit();
}
