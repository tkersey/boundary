// Copyright (c) 2026 Boundary contributors. MIT license.
//! One body and constructor, interpreted into two different answer types.
const source = @import("../source.zig");
const state = @import("../library/state.zig");
const p = @import("boundary_data_v2").program;

pub fn build(b: *source.Builder) source.Error!source.ast.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const region = b.region();
    const region_type = try b.schema(.{ .internal = .{ .region = region } });
    const family = try state.family(b, "example/answers", integer);
    const captures = &.{ integer, family.get_capability, family.put_capability };
    const optional = try state.interpret(b, family, integer, region, captures, .{ .effects = &.{} }, .optional);
    const paired = try state.interpret(b, family, integer, region, captures, .{ .effects = &.{} }, .with_state);
    const result = try b.schema(.{ .product = &.{ optional.answer, paired.answer } });
    const main = try b.declare(&.{}, result, &.{}, &.{});
    const inside = try b.declare(&.{region_type}, result, &.{}, &.{region});
    const body = try b.declare(&.{ family.get_capability, family.put_capability }, integer, &.{family.get}, &.{region});
    const x = try b.variable(integer);
    const plus = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ try b.reference(x), try b.constant(u64, 1) }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
    try b.define(body, try b.bind(x, try b.term(.{ .perform = .{ .effect = family.get, .capability = try b.reference(b.parameter(body, 0)), .payload = try b.constant(void, {}) } }), try b.pure(plus)));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ family.get_capability, family.put_capability }, .result = integer, .effects = &.{family.get}, .regions = &.{region} } } });
    const closure = try b.lambda(body, body_type);
    const cell = try b.variable(optional.cell);
    const first = try b.variable(optional.answer);
    const second = try b.variable(paired.answer);
    const first_term = try b.term(.{ .handle = .{ .handler = optional.handler, .body = closure, .state = &.{try b.reference(cell)} } });
    const second_term = try b.term(.{ .handle = .{ .handler = paired.handler, .body = closure, .state = &.{try b.reference(cell)} } });
    const pair = try b.pure(try b.primitive(result, .product, &.{ try b.reference(first), try b.reference(second) }, 0));
    try b.define(inside, try b.bind(cell, try b.pure(try b.primitive(optional.cell, .cell_new, &.{ try b.reference(b.parameter(inside, 0)), try b.constant(u64, 9) }, 0)), try b.bind(first, first_term, try b.bind(second, second_term, pair))));
    const inside_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{region_type}, .result = result, .regions = &.{region} } } });
    try b.define(main, try b.term(.{ .with_region = .{ .region = region, .body = try b.lambda(inside, inside_type) } }));
    return b.module(main, unit);
}
