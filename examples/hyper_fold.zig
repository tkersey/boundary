//! Runtime two-input demand-driven map/zip/fold, with an independent direct path.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const hyper = boundary.library.hyper;
const Id = source.Id;
const Types = struct { integer: Id, sequence: Id, state: Id, input: Id, delayed: Id, consume: Id, pair: hyper.Pair };
fn types(b: *source.Builder) !Types {
    const cache = try b.specialization(Types, "example.hyper-fold/v1", .{});
    if (cache.cached) |t| return t;
    const integer = try b.scalar(u64);
    const sequence = try b.schema(.{ .vector = .{ .element = integer, .maximum = 4096 } });
    const state = try b.schema(.{ .product = &.{ sequence, integer, integer } });
    const input = try b.schema(.{ .product = &.{ sequence, sequence, integer } });
    const delayed = try b.reserveSchema();
    const consume = try b.reserveSchema();
    const pair = try hyper.pairWith(b, consume, integer, &.{ state, sequence, integer, delayed });
    const captures = &.{ state, sequence, integer, delayed, consume, pair.peer_forward, pair.peer_backward, pair.answer_forward, pair.answer_backward };
    try b.defineSchema(delayed, .{ .internal = .{ .computation = .{ .parameters = &.{}, .result = integer, .capture_bound = captures } } });
    try b.defineSchema(consume, .{ .internal = .{ .computation = .{ .parameters = &.{delayed}, .result = delayed, .capture_bound = captures } } });
    return cache.finish(b, .{ .integer = integer, .sequence = sequence, .state = state, .input = input, .delayed = delayed, .consume = consume, .pair = pair });
}
fn field(b: *source.Builder, schema: Id, value: Id, index: Id) !Id {
    return b.primitive(schema, .field, &.{value}, index);
}
fn checked(b: *source.Builder, op: boundary.data.program.Opcode, left: Id, right: Id) !Id {
    return b.value(.{ .schema = try b.scalar(u64), .expression = .{ .primitive = .{ .opcode = op, .operands = &.{ left, right }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
}
fn element(b: *source.Builder, t: Types, state: Id) !Id {
    const optional = try b.schema(.{ .sum = &.{ try b.scalar(void), t.integer } });
    const selected = try b.primitive(optional, .sequence_get, &.{ try field(b, t.sequence, state, 0), try field(b, t.integer, state, 1) }, 0);
    return b.value(.{ .schema = t.integer, .expression = .{ .primitive = .{ .opcode = .variant_payload, .operands = &.{selected}, .immediate = 1, .failures = &.{.{ .kind = .invalid_variant, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
}
fn available(b: *source.Builder, t: Types, state: Id) !Id {
    const length = try b.primitive(t.integer, .sequence_length, &.{try field(b, t.sequence, state, 0)}, 0);
    return b.primitive(try b.scalar(bool), .less, &.{ try field(b, t.integer, state, 1), length }, 0);
}
fn successor(b: *source.Builder, t: Types, state: Id) !Id {
    return b.primitive(t.state, .product, &.{ try field(b, t.sequence, state, 0), try checked(b, .integer_add, try field(b, t.integer, state, 1), try b.constant(u64, 1)), try field(b, t.integer, state, 2) }, 0);
}
// Independently authored pure transformations; both preserve checked failure.
fn mapLeft(b: *source.Builder, value: Id) !Id {
    return checked(b, .integer_add, value, try b.constant(u64, 1));
}
fn mapRight(b: *source.Builder, value: Id) !Id {
    return checked(b, .integer_mul, value, try b.constant(u64, 2));
}
const Producer = struct {
    pub fn emit(b: *source.Builder, q: hyper.Query) !Id {
        const t = try types(b);
        const work = try b.declare(&.{}, t.integer, &.{}, &.{});
        const mapped = try b.declare(&.{}, t.integer, &.{}, &.{});
        try b.define(mapped, try b.pure(try mapLeft(b, try element(b, t, q.state))));
        const answer = try b.variable(q.types.answer_backward);
        const consumer = try b.variable(t.consume);
        const result = try b.variable(t.delayed);
        const apply = try b.term(.{ .apply = .{ .computation = try b.reference(consumer), .arguments = &.{try b.lambda(mapped, t.delayed)} } });
        const observed = try b.bind(answer, try q.ask(b, try successor(b, t, q.state)), try b.bind(consumer, try hyper.force(b, try b.reference(answer)), try b.bind(result, apply, try hyper.force(b, try b.reference(result)))));
        try b.define(work, try b.term(.{ .conditional = .{ .condition = try available(b, t, q.state), .when_true = observed, .when_false = try b.pure(try b.constant(u64, 0)) } }));
        return b.pure(try b.lambda(work, q.types.answer_forward));
    }
};
const Consumer = struct {
    pub fn emit(b: *source.Builder, q: hyper.Query) !Id {
        const t = try types(b);
        const function = try b.declare(&.{t.delayed}, t.delayed, &.{}, &.{});
        const work = try b.declare(&.{}, t.integer, &.{}, &.{});
        const y = try b.variable(t.integer);
        const x = try b.variable(t.integer);
        const answer = try b.variable(q.types.answer_backward);
        const tail = try b.variable(t.integer);
        const sum = try checked(b, .integer_add, try checked(b, .integer_add, try b.reference(x), try b.reference(y)), try b.reference(tail));
        const next = try b.bind(answer, try q.ask(b, try successor(b, t, q.state)), try b.bind(tail, try hyper.force(b, try b.reference(answer)), try b.pure(sum)));
        const mapped = try b.bind(y, try b.pure(try mapRight(b, try element(b, t, q.state))), try b.bind(x, try hyper.force(b, try b.reference(b.parameter(function, 0))), next));
        const zero = try b.pure(try b.constant(u64, 0));
        const within = try b.primitive(try b.scalar(bool), .less, &.{ try field(b, t.integer, q.state, 1), try field(b, t.integer, q.state, 2) }, 0);
        const bounded = try b.term(.{ .conditional = .{ .condition = within, .when_true = mapped, .when_false = zero } });
        try b.define(work, try b.term(.{ .conditional = .{ .condition = try available(b, t, q.state), .when_true = bounded, .when_false = zero } }));
        try b.define(function, try b.pure(try b.lambda(work, t.delayed)));
        const descriptor = try b.declare(&.{}, t.consume, &.{}, &.{});
        try b.define(descriptor, try b.pure(try b.lambda(function, t.consume)));
        return b.pure(try b.lambda(descriptor, q.types.answer_forward));
    }
};
const Application = struct {
    var direct = false;
    var materialized = false;
    pub fn emit(b: *source.Builder) !source.Module {
        const t = try types(b);
        const entry = try b.declare(&.{t.input}, t.integer, &.{}, &.{});
        const input = try b.reference(b.parameter(entry, 0));
        if (materialized) {
            const loop = try materializedFold(b, t);
            try b.define(entry, try b.term(.{ .call = .{ .function = loop, .arguments = &.{input} } }));
        } else if (direct) {
            const loop = try directFold(b, t);
            try b.define(entry, try b.term(.{ .call = .{ .function = loop, .arguments = &.{ input, try b.constant(u64, 0) } } }));
        } else {
            const producer = try hyper.ana(b, t.pair, t.state, Producer);
            const consumer = try hyper.ana(b, hyper.swap(t.pair), t.state, Consumer);
            const left = try b.variable(t.pair.forward);
            const right = try b.variable(t.pair.backward);
            const peer = try b.declare(&.{}, t.pair.backward, &.{}, &.{});
            try b.define(peer, try b.pure(try b.reference(right)));
            const answer = try b.variable(t.pair.answer_forward);
            const run = try b.bind(answer, try hyper.invoke(b, try b.reference(left), try b.lambda(peer, t.pair.peer_backward)), try hyper.force(b, try b.reference(answer)));
            const limit = try field(b, t.integer, input, 2);
            const ls = try b.primitive(t.state, .product, &.{ try field(b, t.sequence, input, 0), try b.constant(u64, 0), limit }, 0);
            const rs = try b.primitive(t.state, .product, &.{ try field(b, t.sequence, input, 1), try b.constant(u64, 0), limit }, 0);
            try b.define(entry, try b.bind(left, try hyper.start(b, producer, ls), try b.bind(right, try hyper.start(b, consumer, rs), run)));
        }
        return b.module(entry, try b.scalar(void));
    }
};
fn directFold(b: *source.Builder, t: Types) !Id {
    const loop = try b.declare(&.{ t.input, t.integer }, t.integer, &.{}, &.{});
    const input = try b.reference(b.parameter(loop, 0));
    const index = try b.reference(b.parameter(loop, 1));
    const limit = try field(b, t.integer, input, 2);
    const ls = try b.primitive(t.state, .product, &.{ try field(b, t.sequence, input, 0), index, limit }, 0);
    const rs = try b.primitive(t.state, .product, &.{ try field(b, t.sequence, input, 1), index, limit }, 0);
    const y = try b.variable(t.integer);
    const x = try b.variable(t.integer);
    const tail = try b.variable(t.integer);
    const sum = try checked(b, .integer_add, try checked(b, .integer_add, try b.reference(x), try b.reference(y)), try b.reference(tail));
    const next = try b.term(.{ .call = .{ .function = loop, .arguments = &.{ input, try checked(b, .integer_add, index, try b.constant(u64, 1)) } } });
    const work = try b.bind(y, try b.pure(try mapRight(b, try element(b, t, rs))), try b.bind(x, try b.pure(try mapLeft(b, try element(b, t, ls))), try b.bind(tail, next, try b.pure(sum))));
    const zero = try b.pure(try b.constant(u64, 0));
    const bounded = try b.term(.{ .conditional = .{ .condition = try b.primitive(try b.scalar(bool), .less, &.{ index, limit }, 0), .when_true = work, .when_false = zero } });
    const right = try b.term(.{ .conditional = .{ .condition = try available(b, t, rs), .when_true = bounded, .when_false = zero } });
    try b.define(loop, try b.term(.{ .conditional = .{ .condition = try available(b, t, ls), .when_true = right, .when_false = zero } }));
    return loop;
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.MissingMode;
    if (args.next() != null) return error.UnexpectedArgument;
    Application.direct = std.mem.eql(u8, mode, "direct") or std.mem.eql(u8, mode, "stats-direct");
    Application.materialized = std.mem.eql(u8, mode, "materialized") or std.mem.eql(u8, mode, "stats-materialized");
    const stats = std.mem.eql(u8, mode, "stats") or std.mem.eql(u8, mode, "stats-direct") or std.mem.eql(u8, mode, "stats-materialized");
    if (!Application.direct and !Application.materialized and !stats and !std.mem.eql(u8, mode, "hyper")) return error.InvalidMode;
    var compiled = try boundary.program.lower(init.gpa, Application);
    defer compiled.deinit();
    const length = try boundary.data.program_image.encodedLength(compiled.program);
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    if (stats) {
        var sequences: usize = 0;
        for (compiled.program.blocks) |block| for (block.instructions) |instruction| {
            switch (instruction.opcode) {
                .sequence, .sequence_append, .sequence_concat => sequences += 1,
                else => {},
            }
        };
        const text = try std.fmt.allocPrint(init.gpa, "{{\"functions\":{d},\"constructors\":{d},\"imageBytes\":{d},\"sequenceBuilders\":{d}}}\n", .{ compiled.program.functions.len, compiled.program.constructors.len, length, sequences });
        defer init.gpa.free(text);
        try writer.interface.writeAll(text);
    } else {
        const bytes = try init.gpa.alloc(u8, length);
        defer init.gpa.free(bytes);
        _ = try compiled.encode(init.gpa, bytes);
        try writer.interface.writeAll(bytes);
    }
    try writer.interface.flush();
}

// Materialize only the demanded prefix, preserving y-map, x-map, then the
// right-associated checked reduction. Materializing an unused suffix would be
// a different observable contract and is deliberately not the comparator.
fn materializedFold(b: *source.Builder, t: Types) !Id {
    const pair = try b.schema(.{ .product = &.{ t.integer, t.integer } });
    const buffer = try b.schema(.{ .vector = .{ .element = pair, .maximum = 4096 } });
    const reduce = try b.declare(&.{ buffer, t.integer, t.integer }, t.integer, &.{}, &.{});
    const values = try b.reference(b.parameter(reduce, 0));
    const remaining = try b.reference(b.parameter(reduce, 1));
    const total = try b.reference(b.parameter(reduce, 2));
    const previous = try checked(b, .integer_sub, remaining, try b.constant(u64, 1));
    const optional = try b.schema(.{ .sum = &.{ try b.scalar(void), pair } });
    const selected = try b.primitive(optional, .sequence_get, &.{ values, previous }, 0);
    const item = try b.value(.{ .schema = pair, .expression = .{ .primitive = .{ .opcode = .variant_payload, .operands = &.{selected}, .immediate = 1, .failures = &.{.{ .kind = .invalid_variant, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
    const accumulated = try checked(b, .integer_add, try checked(b, .integer_add, try field(b, t.integer, item, 0), try field(b, t.integer, item, 1)), total);
    const recur = try b.term(.{ .call = .{ .function = reduce, .arguments = &.{ values, previous, accumulated } } });
    try b.define(reduce, try b.term(.{ .conditional = .{ .condition = try b.primitive(try b.scalar(bool), .equal, &.{ remaining, try b.constant(u64, 0) }, 0), .when_true = try b.pure(total), .when_false = recur } }));
    const gather = try b.declare(&.{ t.input, t.integer, buffer }, t.integer, &.{}, &.{});
    const input = try b.reference(b.parameter(gather, 0));
    const index = try b.reference(b.parameter(gather, 1));
    const prior = try b.reference(b.parameter(gather, 2));
    const limit = try field(b, t.integer, input, 2);
    const ls = try b.primitive(t.state, .product, &.{ try field(b, t.sequence, input, 0), index, limit }, 0);
    const rs = try b.primitive(t.state, .product, &.{ try field(b, t.sequence, input, 1), index, limit }, 0);
    const y = try b.variable(t.integer);
    const x = try b.variable(t.integer);
    const mapped = try b.primitive(pair, .product, &.{ try b.reference(x), try b.reference(y) }, 0);
    const appended = try b.value(.{ .schema = buffer, .expression = .{ .primitive = .{ .opcode = .sequence_append, .operands = &.{ prior, mapped }, .failures = &.{.{ .kind = .capacity_exceeded, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
    const next = try b.term(.{ .call = .{ .function = gather, .arguments = &.{ input, try checked(b, .integer_add, index, try b.constant(u64, 1)), appended } } });
    const work = try b.bind(y, try b.pure(try mapRight(b, try element(b, t, rs))), try b.bind(x, try b.pure(try mapLeft(b, try element(b, t, ls))), next));
    const done = try b.term(.{ .call = .{ .function = reduce, .arguments = &.{ prior, index, try b.constant(u64, 0) } } });
    const bounded = try b.term(.{ .conditional = .{ .condition = try b.primitive(try b.scalar(bool), .less, &.{ index, limit }, 0), .when_true = work, .when_false = done } });
    const right = try b.term(.{ .conditional = .{ .condition = try available(b, t, rs), .when_true = bounded, .when_false = done } });
    try b.define(gather, try b.term(.{ .conditional = .{ .condition = try available(b, t, ls), .when_true = right, .when_false = done } }));
    const entry = try b.declare(&.{t.input}, t.integer, &.{}, &.{});
    try b.define(entry, try b.term(.{ .call = .{ .function = gather, .arguments = &.{ try b.reference(b.parameter(entry, 0)), try b.constant(u64, 0), try b.primitive(buffer, .sequence, &.{}, 0) } } }));
    return entry;
}

/// Reuse the exact staged workloads in compiler measurements.
pub fn emitWorkload(b: *source.Builder, mode: enum { hyper, direct, materialized }) !source.Module {
    Application.direct = mode == .direct;
    Application.materialized = mode == .materialized;
    return Application.emit(b);
}
