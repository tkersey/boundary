//! Pure adaptive reciprocal queries over distinct Boolean/integer endpoints.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const hyper = boundary.library.hyper;
const Id = source.Id;
const Types = struct { integer: Id, boolean: Id, producer: Id, consumer: Id, input: Id, pair: hyper.Pair };
fn types(b: *source.Builder) !Types {
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const producer = try b.schema(.{ .product = &.{ integer, integer } });
    const consumer = try b.schema(.{ .product = &.{ integer, integer, boolean } });
    return .{ .integer = integer, .boolean = boolean, .producer = producer, .consumer = consumer, .input = try b.schema(.{ .product = &.{ integer, integer, integer, boolean } }), .pair = try hyper.pairWith(b, boolean, integer, &.{ producer, consumer, integer, boolean }) };
}
fn field(b: *source.Builder, schema: Id, value: Id, index: Id) !Id {
    return b.primitive(schema, .field, &.{value}, index);
}
fn equal(b: *source.Builder, a: Id, z: Id) !Id {
    return b.primitive(try b.scalar(bool), .equal, &.{ a, z }, 0);
}
fn add(b: *source.Builder, a: Id, n: u64) !Id {
    return b.value(.{ .schema = try b.scalar(u64), .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ a, try b.constant(u64, n) }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
}
const Producer = struct {
    pub fn emit(b: *source.Builder, q: hyper.Query) !Id {
        const t = try types(b);
        const stage = try field(b, t.integer, q.state, 0);
        const seed = try field(b, t.integer, q.state, 1);
        const first = try b.variable(t.boolean);
        const second = try b.variable(t.boolean);
        const first_delay = try b.variable(q.types.answer_backward);
        const second_delay = try b.variable(q.types.answer_backward);
        const requested_stage = try b.primitive(t.integer, .select, &.{ try b.reference(first), try b.constant(u64, 2), try b.constant(u64, 3) }, 0);
        const first_state = try b.primitive(t.producer, .product, &.{ try b.constant(u64, 1), seed }, 0);
        const second_state = try b.primitive(t.producer, .product, &.{ requested_stage, seed }, 0);
        const tens = try b.primitive(t.integer, .select, &.{ try b.reference(first), try b.constant(u64, 10), try b.constant(u64, 20) }, 0);
        const result = try b.term(.{ .conditional = .{ .condition = try b.reference(second), .when_true = try b.pure(try add(b, tens, 1)), .when_false = try b.pure(try add(b, tens, 2)) } });
        const adaptive = try b.bind(first_delay, try q.ask(b, first_state), try b.bind(first, try hyper.force(b, try b.reference(first_delay)), try b.bind(second_delay, try q.ask(b, second_state), try b.bind(second, try hyper.force(b, try b.reference(second_delay)), result))));
        const later = try b.term(.{ .conditional = .{ .condition = try equal(b, stage, try b.constant(u64, 2)), .when_true = try b.pure(try add(b, seed, 10)), .when_false = try b.pure(try add(b, seed, 20)) } });
        const leaf = try b.term(.{ .conditional = .{ .condition = try equal(b, stage, try b.constant(u64, 1)), .when_true = try b.pure(seed), .when_false = later } });
        const thunk = try b.declare(&.{}, t.integer, &.{}, &.{});
        try b.define(thunk, try b.term(.{ .conditional = .{ .condition = try equal(b, stage, try b.constant(u64, 0)), .when_true = adaptive, .when_false = leaf } }));
        return b.pure(try b.lambda(thunk, q.types.answer_forward));
    }
};
const Consumer = struct {
    var invert = false;
    pub fn emit(b: *source.Builder, q: hyper.Query) !Id {
        const t = try types(b);
        const answer = try b.variable(t.integer);
        const delayed = try b.variable(q.types.answer_backward);
        const advanced = try add(b, try b.reference(answer), 1);
        const matches = try b.primitive(t.boolean, .select, &.{ try equal(b, advanced, try field(b, t.integer, q.state, 0)), try b.constant(bool, true), try equal(b, advanced, try field(b, t.integer, q.state, 1)) }, 0);
        const result = if (invert) try b.primitive(t.boolean, .boolean_not, &.{matches}, 0) else matches;
        const queried = try b.bind(delayed, try q.ask(b, q.state), try b.bind(answer, try hyper.force(b, try b.reference(delayed)), try b.pure(result)));
        const thunk = try b.declare(&.{}, t.boolean, &.{}, &.{});
        try b.define(thunk, try b.term(.{ .conditional = .{ .condition = try field(b, t.boolean, q.state, 2), .when_true = try b.pure(try b.constant(bool, true)), .when_false = queried } }));
        return b.pure(try b.lambda(thunk, q.types.answer_forward));
    }
};
const Reversed = struct {
    pub fn emit(b: *source.Builder, q: hyper.Query) !Id {
        return b.pure(try hyper.deferValue(b, q.types.answer_forward, try b.constant(bool, true)));
    }
};
fn support(b: *source.Builder, t: Types) !Id {
    const f = try b.declare(&.{ t.pair.forward, t.pair.backward }, t.integer, &.{}, &.{});
    const peer = try b.declare(&.{}, t.pair.backward, &.{}, &.{});
    try b.define(peer, try b.pure(try b.reference(b.parameter(f, 1))));
    const answer = try b.variable(t.pair.answer_forward);
    try b.define(f, try b.bind(answer, try hyper.invoke(b, try b.reference(b.parameter(f, 0)), try b.lambda(peer, t.pair.peer_backward)), try hyper.force(b, try b.reference(answer))));
    return f;
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.MissingMode;
    if (args.next() != null) return error.UnexpectedArgument;
    var b = source.Builder.init(init.gpa);
    defer b.deinit();
    const t = try types(&b);
    var entry: Id = undefined;
    var imports: []const boundary.data.component.Symbol = &.{};
    var borrows: []const boundary.data.borrow_contract.Summary = &.{};
    var symbol: []const u8 = "create";
    if (std.mem.eql(u8, mode, "producer")) entry = (try hyper.ana(&b, t.pair, t.producer, Producer)).function else if (std.mem.eql(u8, mode, "producer-reversed")) entry = (try hyper.ana(&b, hyper.swap(t.pair), t.producer, Reversed)).function else if (std.mem.eql(u8, mode, "consumer") or std.mem.eql(u8, mode, "consumer-invert")) {
        Consumer.invert = std.mem.eql(u8, mode, "consumer-invert");
        entry = (try hyper.ana(&b, hyper.swap(t.pair), t.consumer, Consumer)).function;
    } else if (std.mem.eql(u8, mode, "support")) {
        entry = try support(&b, t);
        symbol = "invoke";
    } else if (std.mem.eql(u8, mode, "entry")) {
        const p = try b.declare(&.{t.producer}, t.pair.forward, &.{}, &.{});
        const c = try b.declare(&.{t.consumer}, t.pair.backward, &.{}, &.{});
        const invoke = try b.declare(&.{ t.pair.forward, t.pair.backward }, t.integer, &.{}, &.{});
        entry = try b.declare(&.{t.input}, t.integer, &.{}, &.{});
        symbol = "main";
        const input = try b.reference(b.parameter(entry, 0));
        const ps = try b.primitive(t.producer, .product, &.{ try b.constant(u64, 0), try field(&b, t.integer, input, 0) }, 0);
        const cs = try b.primitive(t.consumer, .product, &.{ try field(&b, t.integer, input, 1), try field(&b, t.integer, input, 2), try field(&b, t.boolean, input, 3) }, 0);
        const pv = try b.variable(t.pair.forward);
        const cv = try b.variable(t.pair.backward);
        try b.define(entry, try b.bind(pv, try b.term(.{ .call = .{ .function = p, .arguments = &.{ps} } }), try b.bind(cv, try b.term(.{ .call = .{ .function = c, .arguments = &.{cs} } }), try b.term(.{ .call = .{ .function = invoke, .arguments = &.{ try b.reference(pv), try b.reference(cv) } } }))));
        imports = try b.allocator().dupe(boundary.data.component.Symbol, &.{ .{ .name = "producer", .reference = .{ .kind = .function, .id = p } }, .{ .name = "consumer", .reference = .{ .kind = .function, .id = c } }, .{ .name = "support", .reference = .{ .kind = .function, .id = invoke } } });
        borrows = try b.allocator().dupe(boundary.data.borrow_contract.Summary, &.{ .{ .function = p }, .{ .function = c }, .{ .function = invoke } });
    } else return error.InvalidMode;
    var compiled = try source.component.compile(init.gpa, b.module(entry, try b.scalar(void)), .{ .imports = imports, .borrows = borrows, .exports = &.{.{ .name = symbol, .reference = .{ .kind = .function, .id = entry } }} });
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.component.encodedLength(compiled.object));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try out.interface.writeAll(bytes);
    try out.interface.flush();
}
