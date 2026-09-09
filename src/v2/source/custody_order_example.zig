// Copyright (c) 2026 Boundary contributors. MIT license.
//! Independent owned suspensions expose lexical cleanup order.
const source = @import("../source.zig");
const gen = @import("../library/generator.zig");
const cleanup = @import("../library/cleanup.zig");
const p = @import("boundary_data_v2").program;

pub const count = 10;
pub const Fixtures = struct { package: p.Id, queue: p.Id, factory: p.Id, release: p.Id };

pub fn define(b: *source.Builder, release: p.Id) source.Error!Fixtures {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const generator = try gen.define(b, "custody/suspend", integer, &.{ unit, integer }, &.{}, .{ .effects = &.{release} });
    const start = try b.declare(&.{ generator.capability, integer }, unit, &.{ release, generator.effect }, &.{});
    const body = try b.declare(&.{}, unit, &.{generator.effect}, &.{});
    const finalizer = try b.declare(&.{try cleanup.exitInfo(b, integer)}, unit, &.{release}, &.{});
    const label = try b.reference(b.parameter(start, 1));
    const perform = try b.term(.{ .perform = .{ .effect = generator.effect, .capability = try b.reference(b.parameter(start, 0)), .payload = label } });
    try b.define(body, try b.bind(try b.variable(unit), perform, try b.pure(try b.constant(void, {}))));
    try b.define(finalizer, try b.term(.{ .perform = .{ .effect = release, .payload = label } }));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{}, .result = unit, .effects = &.{generator.effect}, .capture_bound = &.{ generator.capability, integer } } } });
    const cleanup_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{try cleanup.exitInfo(b, integer)}, .result = unit, .effects = &.{release}, .capture_bound = &.{integer} } } });
    try b.define(start, try b.term(.{ .protect = .{ .body = try b.lambda(body, body_type), .cleanup = try b.lambda(finalizer, cleanup_type) } }));
    const start_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ generator.capability, integer }, .result = unit, .effects = &.{ release, generator.effect } } } });
    const factory = try b.declare(&.{integer}, generator.package, &.{release}, &.{});
    const answer = try b.variable(generator.answer);
    const done = try b.variable(unit);
    const yielded = try b.variable(generator.yielded);
    const ignored_label = try b.variable(integer);
    const package = try b.variable(generator.package);
    const reject = try b.term(.{ .fail = try b.constant(u64, 99) });
    const unpack = try b.term(.{ .unpack_product = .{ .value = try b.reference(yielded), .variables = &.{ ignored_label, package }, .body = try b.pure(try b.reference(package)) } });
    const matched = try b.term(.{ .match_sum = .{ .value = try b.reference(answer), .cases = &.{ .{ .variable = done, .body = reject }, .{ .variable = yielded, .body = unpack } } } });
    const installed = try b.term(.{ .handle = .{ .handler = generator.handler, .body = try b.lambda(start, start_type), .arguments = &.{try b.reference(b.parameter(factory, 0))} } });
    try b.define(factory, try b.bind(answer, installed, matched));
    return .{ .package = generator.package, .queue = try b.schema(.{ .seq = generator.package }), .factory = factory, .release = release };
}

pub fn build(b: *source.Builder, fixtures: Fixtures, mode: u8) source.Error!p.Id {
    const integer = try b.scalar(u64);
    const queue = fixtures.queue;
    const release = fixtures.release;
    const helper = try b.declare(&.{ queue, queue }, integer, &.{release}, &.{});
    const length = try observation(b, helper, queue, mode);
    const failure = try b.term(.{ .fail = try b.constant(u64, 8) });
    const fails = if (mode == 7) failure else try b.bind(try b.variable(integer), failure, try b.term(.{ .fail = try b.primitive(integer, .sequence_length, &.{try b.reference(b.parameter(helper, if (mode == 2) 0 else 1))}, 0) }));
    const outer = try b.bind(try b.variable(integer), try b.pure(length), fails);
    const inner = try b.bind(try b.variable(queue), try b.pure(try b.reference(b.parameter(helper, 1))), try b.term(.{ .fail = try b.constant(u64, 8) }));
    const held = try b.variable(queue);
    const condition = try b.primitive(try b.scalar(bool), .equal, &.{ length, try b.primitive(integer, .sequence_length, &.{try b.reference(held)}, 0) }, 0);
    const branches = try b.term(.{ .conditional = .{ .condition = condition, .when_true = try b.term(.{ .fail = try b.constant(u64, 8) }), .when_false = try b.term(.{ .fail = try b.constant(u64, 9) }) } });
    const live_inner = try b.bind(held, try b.pure(try b.reference(b.parameter(helper, 1))), branches);
    const returned_inner = try b.bind(held, try b.pure(try b.reference(b.parameter(helper, 1))), try b.pure(try b.constant(u64, 3)));
    const after_inner = try b.bind(try b.variable(integer), returned_inner, failure);
    try b.define(helper, try b.term(.{ .yield_then = if (mode == 9) after_inner else if (mode == 4) live_inner else if (mode == 1) inner else outer }));
    const entry = try b.declare(&.{}, integer, &.{release}, &.{});
    const first = try b.variable(fixtures.package);
    const second = try b.variable(fixtures.package);
    const called = try b.term(.{ .call = .{ .function = helper, .arguments = &.{
        try b.primitive(queue, .sequence, &.{try b.reference(if (mode == 3) second else first)}, 0),
        try b.primitive(queue, .sequence, &.{try b.reference(if (mode == 3) first else second)}, 0),
    } } });
    const with_second = try b.bind(second, try b.term(.{ .call = .{ .function = fixtures.factory, .arguments = &.{try b.constant(u64, 2)} } }), called);
    try b.define(entry, try b.bind(first, try b.term(.{ .call = .{ .function = fixtures.factory, .arguments = &.{try b.constant(u64, 1)} } }), with_second));
    return entry;
}

fn observation(b: *source.Builder, helper: p.Id, queue: p.Id, mode: u8) source.Error!p.Id {
    const integer = try b.scalar(u64);
    const first = try b.reference(b.parameter(helper, 0));
    const second = try b.reference(b.parameter(helper, 1));
    const items = switch (mode) {
        2 => second,
        5 => try b.primitive(try b.schema(.{ .seq = queue }), .sequence, &.{first}, 0),
        6 => try b.primitive(queue, .move, &.{first}, 0),
        7 => try b.primitive(queue, .sequence_concat, &.{ second, first }, 0),
        8 => {
            const captured = try b.declare(&.{}, queue, &.{}, &.{});
            try b.define(captured, try b.pure(first));
            const signature = try b.schema(.{ .internal = .{ .computation = .{
                .parameters = &.{},
                .result = queue,
                .effects = &.{},
                .capture_bound = &.{queue},
                .use = .linear,
            } } });
            const sum = try b.schema(.{ .sum = &.{ try b.scalar(void), signature } });
            const variant = try b.primitive(sum, .variant, &.{try b.lambda(captured, signature)}, 1);
            return b.primitive(integer, .variant_tag, &.{variant}, 0);
        },
        else => first,
    };
    return b.primitive(integer, .sequence_length, &.{items}, 0);
}
