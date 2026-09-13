// Copyright (c) 2026 Boundary contributors. MIT license.
//! A small deterministic source sample, constructed only through the public builder.
//! Generation depth bounds authoring work, never execution or semantic recursion.
const boundary = @import("boundary");
const source = boundary.source;
const p = boundary.data_v2.program;
pub const count = 16;

fn next(state: *u32) u32 {
    state.* = state.* *% 1664525 +% 1013904223;
    return state.*;
}

const Expression = struct {
    builder: *source.Builder,
    integer: p.Id,
    pair: p.Id,
    fault: p.Id,
    captured: p.Id,
    argument: p.Id,
    state: u32,

    fn make(self: *Expression, depth: u32) source.Error!p.Id {
        const choice = next(&self.state);
        if (depth == 0) return switch (choice % 3) {
            0 => self.captured,
            1 => self.argument,
            else => self.builder.constant(u64, choice % 7),
        };
        const left = try self.make(depth - 1);
        const right = try self.make(depth - 1);
        if (choice % 4 == 3) {
            const pair = try self.builder.primitive(self.pair, .product, &.{ left, right }, 0);
            return self.builder.primitive(self.integer, .field, &.{pair}, (choice >> 8) & 1);
        }
        const opcode: p.Opcode = switch (choice % 3) {
            0 => .integer_add,
            1 => .integer_sub,
            else => .integer_mul,
        };
        return self.builder.value(.{ .schema = self.integer, .expression = .{ .primitive = .{
            .opcode = opcode,
            .operands = &.{ left, right },
            .failures = &.{.{ .kind = .arithmetic_overflow, .value = self.fault }},
        } } });
    }
};

fn computation(b: *source.Builder, parameters: []const p.Id, result: p.Id, effects: []const p.Id, captures: []const p.Id) source.Error!p.Id {
    return b.schema(.{ .internal = .{ .computation = .{
        .parameters = parameters,
        .result = result,
        .effects = effects,
        .capture_bound = captures,
    } } });
}

pub fn build(b: *source.Builder, seed: u32) source.Error!source.Module {
    if (seed >= count) return error.InvalidSource;
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const pair = try b.schema(.{ .product = &.{ integer, integer } });
    const exit_info = try boundary.library.cleanup.exitInfo(b, integer);
    const ask = try b.effect(.{ .identity = "generated/input", .payload = integer, .result = integer });
    const release = try b.effect(.{ .identity = "generated/cleanup", .payload = exit_info, .result = unit });
    const main = try b.declare(&.{integer}, integer, &.{ ask, release }, &.{});
    const body = try b.declare(&.{}, integer, &.{ask}, &.{});
    const helper = try b.declare(&.{integer}, integer, &.{}, &.{});
    const cleanup = try b.declare(&.{exit_info}, unit, &.{release}, &.{});
    const received = try b.variable(integer);
    const shadow = try b.variable(integer);
    var expression: Expression = .{
        .builder = b,
        .integer = integer,
        .pair = pair,
        .fault = try b.failureLiteral(try b.constant(u64, 1000 + seed)),
        .captured = try b.reference(received),
        .argument = try b.reference(b.parameter(helper, 0)),
        .state = seed ^ 0x9e3779b9,
    };
    const calculated = try b.pure(try expression.make(3 + seed % 3));
    try b.define(helper, if (seed & 1 != 0) try b.term(.{ .yield_then = calculated }) else calculated);
    const helper_type = try computation(b, &.{integer}, integer, &.{}, &.{integer});
    const applied = try b.term(.{ .apply = .{
        .computation = try b.lambda(helper, helper_type),
        .arguments = &.{try b.reference(shadow)},
    } });
    const request = try b.term(.{ .perform = .{
        .effect = ask,
        .payload = try b.reference(b.parameter(main, 0)),
    } });
    try b.define(body, try b.bind(received, request, try b.bind(shadow, try b.pure(try b.constant(u64, seed + 5)), applied)));
    const cleanup_request = try b.term(.{ .perform = .{
        .effect = release,
        .payload = try b.reference(b.parameter(cleanup, 0)),
    } });
    const finish = if (seed & 8 != 0) try b.term(.{ .fail = try b.constant(u64, 2000 + seed) }) else try b.pure(try b.constant(void, {}));
    const cleaned = try b.bind(try b.variable(unit), cleanup_request, finish);
    try b.define(cleanup, if (seed & 2 != 0) try b.term(.{ .yield_then = cleaned }) else cleaned);
    try b.define(main, try b.term(.{ .protect = .{
        .body = try b.lambda(body, try computation(b, &.{}, integer, &.{ask}, &.{integer})),
        .cleanup = try b.lambda(cleanup, try computation(b, &.{exit_info}, unit, &.{release}, &.{})),
    } }));
    return b.module(main, integer);
}
