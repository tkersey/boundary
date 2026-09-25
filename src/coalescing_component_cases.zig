// Copyright (c) 2026 Boundary contributors. MIT license.
//! Independently emitted object witnesses, with no emitter cache or shared builder.
const std = @import("std");
const source = @import("source.zig");
const data = @import("boundary_data");
const Id = data.program.Id;
pub const Kind = enum { leaf, client };

pub fn emit(a: std.mem.Allocator, kind: Kind, mode: data.coalescing.Mode) ![]u8 {
    var builder = source.Builder.init(a);
    defer builder.deinit();
    const integer = try builder.scalar(u64);
    const unit = try builder.scalar(void);
    var compiled = switch (kind) {
        .leaf => try leaf(a, &builder, integer, unit, mode),
        .client => try client(a, &builder, integer, unit, mode),
    };
    defer compiled.deinit();
    const bytes = try a.alloc(u8, try data.component.encodedLength(compiled.object));
    errdefer a.free(bytes);
    _ = try compiled.encode(a, bytes);
    return bytes;
}

fn leaf(a: std.mem.Allocator, b: *source.Builder, integer: Id, unit: Id, mode: data.coalescing.Mode) !source.component.Compiled {
    const main = try b.declare(&.{integer}, integer, &.{}, &.{});
    const helper = try b.declare(&.{integer}, integer, &.{}, &.{});
    const shape = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{integer},
        .result = integer,
        .capture_bound = &.{integer},
        .use = .reusable,
    } } });
    const failure = try b.failureLiteral(try b.constant(void, {}));
    const sum = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{
        .opcode = .integer_add,
        .operands = &.{ try b.reference(b.parameter(helper, 0)), try b.reference(b.parameter(main, 0)) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = failure }},
    } } });
    try b.define(helper, try b.pure(sum));
    const closure = try b.variable(shape);
    const apply = try b.term(.{ .apply = .{
        .computation = try b.reference(closure),
        .arguments = &.{try b.constant(u64, 10)},
    } });
    try b.define(main, try b.bind(closure, try b.pure(try b.lambda(helper, shape)), apply));
    return source.component.compileObserved(a, b.module(main, unit), .{
        .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = main } }},
    }, .{ .coalescing = .{ .mode = mode } });
}

fn client(a: std.mem.Allocator, b: *source.Builder, integer: Id, unit: Id, mode: data.coalescing.Mode) !source.component.Compiled {
    const pair = try b.schema(.{ .product = &.{ integer, integer } });
    const first = try b.declare(&.{integer}, integer, &.{}, &.{});
    const second = try b.declare(&.{integer}, integer, &.{}, &.{});
    const main = try b.declare(&.{}, pair, &.{}, &.{});
    const left = try b.variable(integer);
    const right = try b.variable(integer);
    const call_left = try b.term(.{ .call = .{
        .function = first,
        .arguments = &.{try b.constant(u64, 3)},
    } });
    const call_right = try b.term(.{ .call = .{
        .function = second,
        .arguments = &.{try b.constant(u64, 7)},
    } });
    const result = try b.primitive(pair, .product, &.{ try b.reference(left), try b.reference(right) }, 0);
    try b.define(main, try b.bind(left, call_left, try b.bind(right, call_right, try b.pure(result))));
    return source.component.compileObserved(a, b.module(main, unit), .{
        .imports = &.{
            .{ .name = "a", .reference = .{ .kind = .function, .id = first } },
            .{ .name = "b", .reference = .{ .kind = .function, .id = second } },
        },
        .borrows = &.{ .{ .function = first }, .{ .function = second } },
        .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = main } }},
    }, .{ .coalescing = .{ .mode = mode } });
}
