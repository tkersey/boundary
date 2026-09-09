// Copyright (c) 2026 Boundary contributors. MIT license.
//! The same row-polymorphic choice library composes with two unrelated results
//! from a finite indexed environmental family.
const source = @import("../source.zig");
const effects = @import("../effect.zig");
const choice = @import("../library/choice.zig");
const p = @import("boundary_data_v2").program;

pub fn build(b: *source.Builder) source.Error!source.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const family = try effects.indexed(b, "example/indexed", &.{
        .{ .identity = "number", .payload = unit, .result = integer },
        .{ .identity = "flag", .payload = unit, .result = boolean },
    });
    const choose = try choice.family(b, "example/row-polymorphic-choice");
    var terms: [2]p.Id = undefined;
    var answers: [2]p.Id = undefined;
    for (0..2) |index| {
        const operation = try family.at(index);
        const interpretation = try choice.first(b, choose, operation.result, &.{}, .{ .effects = &.{operation.effect} });
        answers[index] = interpretation.answer;
        const body = try b.declare(&.{choose.capability}, operation.result, &.{ operation.effect, choose.effect }, &.{});
        const picked = try b.term(.{ .perform = .{ .effect = choose.effect, .capability = try b.reference(b.parameter(body, 0)), .payload = try b.constant(void, {}) } });
        const indexed = try b.term(.{ .perform = .{ .effect = operation.effect, .payload = try b.constant(void, {}) } });
        try b.define(body, try b.bind(try b.variable(boolean), picked, indexed));
        const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{choose.capability}, .result = operation.result, .effects = &.{ operation.effect, choose.effect } } } });
        terms[index] = try b.term(.{ .handle = .{ .handler = interpretation.handler, .body = try b.lambda(body, body_type) } });
    }
    const result = try b.schema(.{ .product = &answers });
    const main = try b.declare(&.{}, result, &.{ (try family.at(0)).effect, (try family.at(1)).effect }, &.{});
    const first = try b.variable(answers[0]);
    const second = try b.variable(answers[1]);
    try b.define(main, try b.bind(first, terms[0], try b.bind(second, terms[1], try b.pure(try b.primitive(result, .product, &.{ try b.reference(first), try b.reference(second) }, 0)))));
    return b.module(main, unit);
}
