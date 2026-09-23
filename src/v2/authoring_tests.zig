const std = @import("std");
const source = @import("source.zig");
const a = @import("authoring.zig");

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
}
