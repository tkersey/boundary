//! Public lazy algebra examples, emitted as ordinary BPI3 Programs.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const hyper = boundary.library.hyper;
const Mode = enum {
    constant,
    project,
    identity,
    distinct,
    compose,
    product,
    sum,
    stream,
    unused_fault,
    fault,
    ana_config,
    ana_capture,
};
const Application = struct {
    var mode: Mode = .constant;
    pub fn emit(b: *source.Builder) !source.Module {
        if (mode == .compose) return composition(b);
        if (mode == .ana_config or mode == .ana_capture) return configuredAna(b, mode == .ana_capture);
        if (mode == .product or mode == .sum or mode == .stream) return aggregate(b, mode);
        const integer = try b.scalar(u64);
        const input = if (mode == .distinct) try b.scalar(bool) else integer;
        const types = try hyper.pair(b, input, integer);
        const entry = try b.declare(&.{}, integer, &.{}, &.{});
        const h = try b.variable(types.forward);
        const answer = try b.variable(types.answer_forward);
        const built = if (mode == .identity) try hyper.identity(b, types) else try hyper.lift(b, types, try transform(b, types, mode == .project or mode == .fault));
        const argument = if (mode == .distinct) try b.constant(bool, false) else if (mode == .fault or mode == .unused_fault) try arithmeticFault(b) else try b.constant(u64, 40);
        const observed = if (mode == .project or mode == .distinct or mode == .fault or mode == .unused_fault) try hyper.project(b, types, try b.reference(h), try hyper.deferValue(b, types.answer_backward, argument)) else try hyper.run(b, types, try b.reference(h));
        try b.define(entry, try b.bind(h, built, try b.bind(answer, observed, try hyper.force(b, try b.reference(answer)))));
        return b.module(entry, try b.scalar(void));
    }
};
fn arithmeticFault(b: *source.Builder) !source.Id {
    return b.value(.{ .schema = try b.scalar(u64), .expression = .{ .primitive = .{
        .opcode = .integer_add,
        .operands = &.{ try b.constant(u64, std.math.maxInt(u64)), try b.constant(u64, 1) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }},
    } } });
}
fn transform(b: *source.Builder, types: hyper.Pair, strict: bool) !source.Id {
    const integer = try b.scalar(u64);
    const function = try b.declare(&.{types.answer_backward}, types.answer_forward, &.{}, &.{});
    if (!strict) {
        try b.define(function, try b.pure(try hyper.deferValue(b, types.answer_forward, try b.constant(u64, 42))));
        return function;
    }
    const thunk = try b.declare(&.{}, integer, &.{}, &.{});
    const value = try b.variable(integer);
    const plus = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{
        .opcode = .integer_add,
        .operands = &.{ try b.reference(value), try b.constant(u64, 2) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }},
    } } });
    try b.define(thunk, try b.bind(value, try hyper.force(b, try b.reference(b.parameter(function, 0))), try b.pure(plus)));
    try b.define(function, try b.pure(try b.lambda(thunk, types.answer_forward)));
    return function;
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    Application.mode = std.meta.stringToEnum(Mode, args.next() orelse return error.MissingMode) orelse return error.InvalidMode;
    if (args.next() != null) return error.UnexpectedArgument;
    var compiled = try boundary.program.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

fn composition(b: *source.Builder) !source.Module {
    const boolean = try b.scalar(bool);
    const integer = try b.scalar(u64);
    const record = try b.schema(.{ .product = &.{ boolean, integer } });
    const group = try hyper.group(b, &.{ boolean, integer, record }, &.{});
    const ab = try group.get(0, 1);
    const bc = try group.get(1, 2);
    const ac = try group.get(0, 2);
    const right_fn = try mappedRight(b, ab);
    const left_fn = try mappedLeft(b, bc, record);
    const entry = try b.declare(&.{}, integer, &.{}, &.{});
    const right = try b.variable(ab.forward);
    const left = try b.variable(bc.forward);
    const composed = try b.variable(ac.forward);
    const delayed = try b.variable(ac.answer_forward);
    const result = try b.variable(record);
    const expected = try b.term(.{ .conditional = .{
        .condition = try b.primitive(boolean, .field, &.{try b.reference(result)}, 0),
        .when_true = try b.pure(try b.primitive(integer, .field, &.{try b.reference(result)}, 1)),
        .when_false = try b.pure(try b.constant(u64, 0)),
    } });
    const observed = try b.bind(delayed, try hyper.project(b, ac, try b.reference(composed), try hyper.deferValue(b, ac.answer_backward, try b.constant(bool, true))), try b.bind(result, try hyper.force(b, try b.reference(delayed)), expected));
    const combined = try b.bind(composed, try hyper.compose(b, group, 0, 1, 2, try b.reference(left), try b.reference(right)), observed);
    const with_left = try b.bind(left, try hyper.lift(b, bc, left_fn), combined);
    try b.define(entry, try b.bind(right, try hyper.lift(b, ab, right_fn), with_left));
    return b.module(entry, try b.scalar(void));
}

fn mappedRight(b: *source.Builder, types: hyper.Pair) !source.Id {
    const function = try b.declare(&.{types.answer_backward}, types.answer_forward, &.{}, &.{});
    const thunk = try b.declare(&.{}, try b.scalar(u64), &.{}, &.{});
    const input = try b.variable(try b.scalar(bool));
    const output = try b.term(.{ .conditional = .{
        .condition = try b.reference(input),
        .when_true = try b.pure(try b.constant(u64, 41)),
        .when_false = try b.pure(try b.constant(u64, 0)),
    } });
    try b.define(thunk, try b.bind(input, try hyper.force(b, try b.reference(b.parameter(function, 0))), output));
    try b.define(function, try b.pure(try b.lambda(thunk, types.answer_forward)));
    return function;
}

fn mappedLeft(b: *source.Builder, types: hyper.Pair, record: source.Id) !source.Id {
    const integer = try b.scalar(u64);
    const function = try b.declare(&.{types.answer_backward}, types.answer_forward, &.{}, &.{});
    const thunk = try b.declare(&.{}, record, &.{}, &.{});
    const input = try b.variable(integer);
    const plus = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{
        .opcode = .integer_add,
        .operands = &.{ try b.reference(input), try b.constant(u64, 1) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }},
    } } });
    const equal = try b.primitive(try b.scalar(bool), .equal, &.{ try b.reference(input), try b.constant(u64, 41) }, 0);
    try b.define(thunk, try b.bind(input, try hyper.force(b, try b.reference(b.parameter(function, 0))), try b.pure(try b.primitive(record, .product, &.{ equal, plus }, 0))));
    try b.define(function, try b.pure(try b.lambda(thunk, types.answer_forward)));
    return function;
}

fn divergent(b: *source.Builder, result: source.Id) !source.Id {
    const function = try b.declare(&.{}, result, &.{}, &.{});
    try b.define(function, try b.term(.{ .call = .{ .function = function, .arguments = &.{} } }));
    return function;
}
fn aggregate(b: *source.Builder, mode: Mode) !source.Module {
    const integer = try b.scalar(u64);
    const unit = try b.scalar(void);
    const entry = try b.declare(&.{}, integer, &.{}, &.{});
    if (mode == .stream) {
        const stream = try hyper.stream(b, integer, &.{});
        const node = try hyper.cons(b, stream, try hyper.deferValue(b, stream.element, try b.constant(u64, 42)), try b.lambda(try divergent(b, stream.node), stream.spine));
        const cell = try b.variable(stream.cell);
        try b.define(entry, try b.term(.{ .match_sum = .{ .value = node, .cases = &.{
            .{ .variable = try b.variable(unit), .body = try b.pure(try b.constant(u64, 0)) },
            .{ .variable = cell, .body = try hyper.force(b, try b.primitive(stream.element, .field, &.{try b.reference(cell)}, 0)) },
        } } }));
    } else {
        const delayed = try hyper.delayed(b, integer, &.{});
        const bad = try b.lambda(try divergent(b, integer), delayed);
        if (mode == .product) {
            const value = try hyper.lazyProduct(b, &.{ try hyper.deferValue(b, delayed, try b.constant(u64, 42)), bad });
            try b.define(entry, try hyper.force(b, try b.primitive(delayed, .field, &.{value}, 0)));
        } else {
            const value = try hyper.lazySum(b, &.{ delayed, delayed }, 0, bad);
            const tag = try b.primitive(integer, .variant_tag, &.{value}, 0);
            const equal = try b.primitive(try b.scalar(bool), .equal, &.{ tag, try b.constant(u64, 0) }, 0);
            try b.define(entry, try b.term(.{ .conditional = .{ .condition = equal, .when_true = try b.pure(try b.constant(u64, 42)), .when_false = try b.pure(try b.constant(u64, 0)) } }));
        }
    }
    return b.module(entry, unit);
}

// The same host emitter type can select different constants or captured bindings.
const ConfiguredStep = struct {
    var value: source.Id = 0;
    pub fn emit(b: *source.Builder, query: hyper.Query) source.Error!source.Id {
        return b.pure(try hyper.deferValue(b, query.types.answer_forward, value));
    }
};
fn configuredAna(b: *source.Builder, capture: bool) !source.Module {
    const integer = try b.scalar(u64);
    const types = try hyper.pair(b, integer, integer);
    const entry = try b.declare(&.{}, integer, &.{}, &.{});
    const first_value = try b.variable(integer);
    const second_value = try b.variable(integer);
    ConfiguredStep.value = if (capture)
        try b.reference(first_value)
    else
        try b.constant(u64, 19);
    const first = try hyper.ana(b, types, integer, ConfiguredStep);
    ConfiguredStep.value = if (capture)
        try b.reference(second_value)
    else
        try b.constant(u64, 23);
    const second = try hyper.ana(b, types, integer, ConfiguredStep);
    const left = try b.variable(integer);
    const right = try b.variable(integer);
    const overflow = try b.failureLiteral(try b.constant(void, {}));
    const sum = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{
        .opcode = .integer_add,
        .operands = &.{ try b.reference(left), try b.reference(right) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = overflow }},
    } } });
    const with_right = try b.bind(right, try observeAna(b, types, second), try b.pure(sum));
    const result = try b.bind(left, try observeAna(b, types, first), with_right);
    const with_second = try b.bind(second_value, try b.pure(try b.constant(u64, 23)), result);
    try b.define(entry, try b.bind(first_value, try b.pure(try b.constant(u64, 19)), with_second));
    return b.module(entry, try b.scalar(void));
}
fn observeAna(b: *source.Builder, types: hyper.Pair, definition: hyper.Ana) !source.Id {
    const participant = try b.variable(types.forward);
    const answer = try b.variable(types.answer_forward);
    const zero = try b.constant(u64, 0);
    const argument = try hyper.deferValue(b, types.answer_backward, zero);
    const projected = try hyper.project(b, types, try b.reference(participant), argument);
    const observed = try b.bind(answer, projected, try hyper.force(b, try b.reference(answer)));
    return b.bind(participant, try hyper.start(b, definition, zero), observed);
}
