// Copyright (c) 2026 Boundary contributors. MIT license.
//! Return-clause writes must preserve the selected reference's lexical owner.
const std = @import("std");
const boundary = @import("boundary");
const Builder = boundary.source.Builder;
const Id = boundary.data_v2.program.Id;
pub const ResultFrom = enum { state, body, pair };
const Types = struct {
    unit: Id,
    region: Id,
    region_type: Id,
    effect: Id,
    cap: Id,
    cell: Id,
    pair: Id,
};
const Handlers = struct { initial: Id, successor: Id, effect: Id, cap: Id, input: Id };

fn types(b: *Builder) !Types {
    const unit = try b.scalar(void);
    const region = b.region();
    const region_type = try b.schema(.{ .internal = .{ .region = region } });
    const effect = try b.effect(.{
        .identity = "regression/return-owner",
        .payload = unit,
        .result = unit,
        .external = false,
    });
    const cap = try b.schema(.{ .internal = .{ .capability = effect } });
    const cell = try b.schema(.{ .internal = .{ .cell = .{ .element = cap, .region = region } } });
    const pair = try b.schema(.{ .product = &.{ cap, cap } });
    return .{
        .unit = unit,
        .region = region,
        .region_type = region_type,
        .effect = effect,
        .cap = cap,
        .cell = cell,
        .pair = pair,
    };
}

fn ownerHandler(b: *Builder, t: Types) !Id {
    const token = try b.schema(.{ .internal = .{ .resumption = .{
        .effect = t.effect,
        .input = t.unit,
        .answer = t.unit,
        .capture_bound = &.{ t.unit, t.cap, t.cell },
        .owned_regions = &.{t.region},
        .handled = &.{t.effect},
        .mode = .deep,
        .use = .linear,
    } } });
    const returns = try b.declare(&.{t.unit}, t.unit, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 0))));
    const clause = try b.declare(&.{ t.unit, token }, t.unit, &.{}, &.{});
    try b.define(clause, try b.term(.{ .resume_value = .{
        .resumption = try b.reference(b.parameter(clause, 1)),
        .argument = try b.constant(void, {}),
    } }));
    return b.handler(.{
        .mode = .deep,
        .input = t.unit,
        .answer = t.unit,
        .return_function = returns,
        .clauses = &.{.{ .effect = t.effect, .function = clause, .resumption = token }},
    });
}

fn returnFunction(
    b: *Builder,
    t: Types,
    input: Id,
    from: ResultFrom,
    younger: bool,
    delegated: bool,
) !Id {
    const parameters = &.{ t.cap, t.cell, input };
    const writer = try b.declare(parameters, t.unit, &.{}, &.{t.region});
    const returned = try b.reference(b.parameter(writer, 2));
    const value = switch (from) {
        .state => try b.reference(b.parameter(writer, 0)),
        .body => returned,
        .pair => try b.primitive(t.cap, .field, &.{returned}, if (younger) 0 else 1),
    };
    try b.define(writer, try b.pure(try b.primitive(t.unit, .cell_set, &.{
        try b.reference(b.parameter(writer, 1)), value,
    }, 0)));
    if (!delegated) return writer;
    const wrapper = try b.declare(parameters, t.unit, &.{}, &.{t.region});
    try b.define(wrapper, try b.term(.{ .call = .{
        .function = writer,
        .arguments = &.{
            try b.reference(b.parameter(wrapper, 0)),
            try b.reference(b.parameter(wrapper, 1)),
            try b.reference(b.parameter(wrapper, 2)),
        },
    } }));
    return wrapper;
}

fn tokenSchema(b: *Builder, t: Types, effect: Id, cap: Id, input: Id, deep: bool) !Id {
    return b.schema(.{ .internal = .{ .resumption = .{
        .effect = effect,
        .input = t.unit,
        .answer = if (deep) t.unit else input,
        .effects = if (deep) &.{} else &.{effect},
        .capture_bound = &.{ t.unit, t.cap, t.cell, t.pair, cap },
        .handled = &.{effect},
        .mode = if (deep) .deep else .shallow,
        .use = .linear,
    } } });
}

fn handlers(b: *Builder, t: Types, from: ResultFrom, younger: bool, delegated: bool) !Handlers {
    const effect = try b.effect(.{
        .identity = "regression/return-successor",
        .payload = t.unit,
        .result = t.unit,
        .external = false,
    });
    const cap = try b.schema(.{ .internal = .{ .capability = effect } });
    const input = switch (from) {
        .state => t.unit,
        .body => t.cap,
        .pair => t.pair,
    };
    const shallow = try tokenSchema(b, t, effect, cap, input, false);
    const deep = try tokenSchema(b, t, effect, cap, input, true);
    const returns = try returnFunction(b, t, input, from, younger, delegated);
    const successor_clause = try b.declare(
        &.{ t.cap, t.cell, t.unit, deep },
        t.unit,
        &.{},
        &.{t.region},
    );
    try b.define(successor_clause, try b.term(.{ .resume_value = .{
        .resumption = try b.reference(b.parameter(successor_clause, 3)),
        .argument = try b.constant(void, {}),
    } }));
    const successor = try b.handler(.{
        .mode = .deep,
        .input = input,
        .answer = t.unit,
        .return_function = returns,
        .state = &.{ t.cap, t.cell },
        .clauses = &.{.{ .effect = effect, .function = successor_clause, .resumption = deep }},
    });
    const initial_returns = try b.declare(&.{ t.cap, t.cell, input }, t.unit, &.{}, &.{t.region});
    try b.define(initial_returns, try b.pure(try b.constant(void, {})));
    const initial_clause = try b.declare(
        &.{ t.cap, t.cell, t.unit, shallow },
        t.unit,
        &.{},
        &.{t.region},
    );
    try b.define(initial_clause, try b.term(.{ .resume_with = .{
        .resumption = try b.reference(b.parameter(initial_clause, 3)),
        .argument = try b.constant(void, {}),
        .handler = successor,
        .state = &.{
            try b.reference(b.parameter(initial_clause, 0)),
            try b.reference(b.parameter(initial_clause, 1)),
        },
    } }));
    const initial = try b.handler(.{
        .mode = .shallow,
        .input = input,
        .answer = t.unit,
        .return_function = initial_returns,
        .state = &.{ t.cap, t.cell },
        .clauses = &.{.{ .effect = effect, .function = initial_clause, .resumption = shallow }},
    });
    return .{
        .initial = initial,
        .successor = successor,
        .effect = effect,
        .cap = cap,
        .input = input,
    };
}

fn finish(b: *Builder, t: Types, owner: Id, middle: Id) !boundary.source.Module {
    const middle_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{ t.cap, t.cap, t.cell },
        .result = t.unit,
        .regions = &.{t.region},
    } } });
    const outer = try b.declare(&.{t.cap}, t.unit, &.{}, &.{});
    const scope = try b.declare(&.{t.region_type}, t.unit, &.{}, &.{t.region});
    const older = try b.reference(b.parameter(outer, 0));
    const allocated = try b.variable(t.cell);
    const allocation = try b.pure(try b.primitive(t.cell, .cell_new, &.{
        try b.reference(b.parameter(scope, 0)), older,
    }, 0));
    const installed = try b.term(.{ .handle = .{
        .handler = owner,
        .body = try b.lambda(middle, middle_type),
        .arguments = &.{ older, try b.reference(allocated) },
    } });
    const read = try b.pure(try b.primitive(t.cap, .cell_get, &.{try b.reference(allocated)}, 0));
    const after = try b.term(.{ .yield_then = try b.bind(
        try b.variable(t.cap),
        read,
        try b.pure(try b.constant(void, {})),
    ) });
    const continued = try b.bind(try b.variable(t.unit), installed, after);
    try b.define(scope, try b.bind(allocated, allocation, continued));
    const scope_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{t.region_type},
        .result = t.unit,
        .capture_bound = &.{t.cap},
        .regions = &.{t.region},
    } } });
    try b.define(outer, try b.term(.{ .with_region = .{
        .region = t.region,
        .body = try b.lambda(scope, scope_type),
    } }));
    const outer_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{t.cap},
        .result = t.unit,
    } } });
    const entry = try b.declare(&.{}, t.unit, &.{}, &.{});
    try b.define(entry, try b.term(.{ .handle = .{
        .handler = owner,
        .body = try b.lambda(outer, outer_type),
    } }));
    return b.module(entry, t.unit);
}

pub fn scenario(
    b: *Builder,
    from: ResultFrom,
    initial: bool,
    younger: bool,
    delegated: bool,
) !boundary.source.Module {
    const t = try types(b);
    const owner = try ownerHandler(b, t);
    const h = try handlers(b, t, from, younger, delegated);
    const middle = try b.declare(&.{ t.cap, t.cap, t.cell }, t.unit, &.{}, &.{t.region});
    const selected = try b.reference(b.parameter(middle, if (younger) 0 else 1));
    const body = try b.declare(&.{h.cap}, h.input, &.{h.effect}, &.{t.region});
    const performed = try b.term(.{ .perform = .{
        .effect = h.effect,
        .capability = try b.reference(b.parameter(body, 0)),
        .payload = try b.constant(void, {}),
    } });
    const result = switch (from) {
        .state => try b.constant(void, {}),
        .body => selected,
        .pair => try b.primitive(t.pair, .product, &.{
            try b.reference(b.parameter(middle, 0)),
            try b.reference(b.parameter(middle, 1)),
        }, 0),
    };
    try b.define(body, try b.bind(try b.variable(t.unit), performed, try b.pure(result)));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{h.cap},
        .result = h.input,
        .effects = &.{h.effect},
        .capture_bound = &.{t.cap},
        .regions = &.{t.region},
    } } });
    try b.define(middle, try b.term(.{ .handle = .{
        .handler = if (initial) h.successor else h.initial,
        .body = try b.lambda(body, body_type),
        .state = &.{ selected, try b.reference(b.parameter(middle, 2)) },
    } }));
    return finish(b, t, owner, middle);
}

pub fn main(init: std.process.Init) !void {
    var count: usize = 0;
    for (std.enums.values(ResultFrom)) |from| {
        for ([_]bool{ false, true }) |initial| {
            for ([_]bool{ false, true }) |younger| {
                for ([_]bool{ false, true }) |delegated| {
                    var b = Builder.init(init.gpa);
                    defer b.deinit();
                    const source = try scenario(&b, from, initial, younger, delegated);
                    if (boundary.program.compile(init.gpa, source)) |result| {
                        var compiled = result;
                        defer compiled.deinit();
                        if (younger) return error.ExpectedBorrowRejection;
                    } else |err| {
                        if (!younger or err != error.InvalidOwnership) return err;
                    }
                    count += 1;
                }
            }
        }
    }
    var buffer: [256]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.print("{d} handler return borrow cases passed\n", .{count});
    try output.interface.flush();
}
