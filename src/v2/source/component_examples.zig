// Copyright (c) 2026 Boundary contributors. MIT license.
//! Three independently authored effectful objects and a second closed wrapper.
const std = @import("std");
const source = @import("../source.zig");
const data = @import("boundary_data");
const p = data.program;
const gen = @import("../library/generator.zig");
const cleanup = @import("../library/cleanup.zig");
pub const Kind = enum { call, state, suspended, double, even, odd };
const Common = struct { unit: p.Id, integer: p.Id, pair: p.Id, read: p.Id, cap: p.Id, callback: p.Id };
fn common(b: *source.Builder) !Common {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const pair = try b.schema(.{ .product = &.{ integer, integer } });
    const read = try b.effect(.{ .identity = "component/counter", .payload = unit, .result = integer, .external = false });
    const cap = try b.schema(.{ .internal = .{ .capability = read } });
    const callback = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{}, .result = integer, .effects = &.{read}, .capture_bound = &.{cap} } } });
    return .{ .unit = unit, .integer = integer, .pair = pair, .read = read, .cap = cap, .callback = callback };
}
fn symbol(name: []const u8, kind: data.relocation.Kind, id: p.Id) data.component.Symbol {
    return .{ .name = name, .reference = .{ .kind = kind, .id = id } };
}
fn add(b: *source.Builder, integer: p.Id, left: p.Id, right: p.Id) !p.Id {
    const failure = try b.failureLiteral(try b.constant(void, {}));
    return b.value(.{ .schema = integer, .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ left, right }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = failure }} } } });
}
pub fn emit(allocator: std.mem.Allocator, kind: Kind) ![]u8 {
    var b = source.Builder.init(allocator);
    defer b.deinit();
    const c = try common(&b);
    const built = switch (kind) {
        .call => try caller(&b, c),
        .state => try stateful(&b, c),
        .suspended => try suspension(&b, c),
        .double => try doubled(&b, c),
        .even => try recursive(&b, c, true),
        .odd => try recursive(&b, c, false),
    };
    var compiled = try source.component.compile(allocator, b.module(built.entry, c.unit), built.interface);
    defer compiled.deinit();
    const bytes = try allocator.alloc(u8, try data.component.encodedLength(compiled.object));
    errdefer allocator.free(bytes);
    _ = try compiled.encode(allocator, bytes);
    return bytes;
}
const Built = struct { entry: p.Id, interface: source.component.Interface };
fn caller(b: *source.Builder, c: Common) !Built {
    const function = try @import("../library/combinators.zig").twice(b, c.callback);
    return .{ .entry = function, .interface = .{
        .imports = try b.allocator().dupe(data.component.Symbol, &.{symbol("read", .effect, c.read)}),
        .exports = try b.allocator().dupe(data.component.Symbol, &.{symbol("twice", .function, function)}),
    } };
}
fn stateful(b: *source.Builder, c: Common) !Built {
    const twice = try b.declare(&.{c.callback}, c.pair, &.{c.read}, &.{});
    const token = try b.schema(.{ .internal = .{ .resumption = .{ .effect = c.read, .input = c.integer, .answer = c.pair, .effects = &.{c.read}, .capture_bound = &.{ c.unit, c.integer, c.cap, c.callback, c.pair }, .handled = &.{c.read}, .escaping = &.{c.read}, .mode = .shallow, .use = .linear } } });
    const returns = try b.declare(&.{ c.integer, c.pair }, c.pair, &.{}, &.{});
    try b.define(returns, try b.pure(try b.reference(b.parameter(returns, 1))));
    const clause = try b.declare(&.{ c.integer, c.unit, token }, c.pair, &.{c.read}, &.{});
    const handler = try b.handler(.{ .mode = .shallow, .input = c.pair, .answer = c.pair, .return_function = returns, .state = &.{c.integer}, .effects = &.{c.read}, .clauses = &.{.{ .effect = c.read, .function = clause, .resumption = token }} });
    const current = try b.reference(b.parameter(clause, 0));
    try b.define(clause, try b.term(.{ .resume_with = .{ .resumption = try b.reference(b.parameter(clause, 2)), .argument = current, .handler = handler, .state = &.{try add(b, c.integer, current, try b.constant(u64, 1))} } }));
    const body = try b.declare(&.{c.cap}, c.pair, &.{c.read}, &.{});
    const callback = try b.declare(&.{}, c.integer, &.{c.read}, &.{});
    try b.define(callback, try b.term(.{ .perform = .{ .effect = c.read, .capability = try b.reference(b.parameter(body, 0)), .payload = try b.constant(void, {}) } }));
    try b.define(body, try b.term(.{ .call = .{ .function = twice, .arguments = &.{try b.lambda(callback, c.callback)} } }));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{c.cap}, .result = c.pair, .effects = &.{c.read} } } });
    const main = try b.declare(&.{}, c.integer, &.{c.read}, &.{});
    const pair = try b.variable(c.pair);
    const value = try b.reference(pair);
    const sum = try add(b, c.integer, try b.primitive(c.integer, .field, &.{value}, 0), try b.primitive(c.integer, .field, &.{value}, 1));
    try b.define(main, try b.bind(pair, try b.term(.{ .handle = .{ .handler = handler, .body = try b.lambda(body, body_type), .state = &.{try b.constant(u64, 41)} } }), try b.pure(sum)));
    return .{ .entry = main, .interface = .{
        .imports = try b.allocator().dupe(data.component.Symbol, &.{symbol("twice", .function, twice)}),
        .borrows = try b.allocator().dupe(data.borrow_contract.Summary, &.{.{ .function = twice }}),
        .exports = try b.allocator().dupe(data.component.Symbol, &.{ symbol("compute", .function, main), symbol("read", .effect, c.read) }),
    } };
}
fn suspension(b: *source.Builder, c: Common) !Built {
    const compute = try b.declare(&.{}, c.integer, &.{c.read}, &.{});
    const release = try b.effect(.{ .identity = "component/release", .payload = c.integer, .result = c.unit });
    const generator = try gen.define(b, "component/yield", c.integer, &.{ c.unit, c.integer }, &.{}, .{ .effects = &.{release} });
    const start = try b.declare(&.{generator.capability}, c.unit, &.{ release, generator.effect }, &.{});
    const value = try b.variable(c.integer);
    const body = try b.declare(&.{}, c.unit, &.{generator.effect}, &.{});
    try b.define(body, try b.bind(try b.variable(c.unit), try b.term(.{ .perform = .{ .effect = generator.effect, .capability = try b.reference(b.parameter(start, 0)), .payload = try b.reference(value) } }), try b.pure(try b.constant(void, {}))));
    const finalizer = try b.declare(&.{try cleanup.exitInfo(b, c.unit)}, c.unit, &.{release}, &.{});
    try b.define(finalizer, try b.term(.{ .perform = .{ .effect = release, .payload = try b.reference(value) } }));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{}, .result = c.unit, .effects = &.{generator.effect}, .capture_bound = &.{ generator.capability, c.integer } } } });
    const cleanup_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{try cleanup.exitInfo(b, c.unit)}, .result = c.unit, .effects = &.{release}, .capture_bound = &.{c.integer} } } });
    try b.define(start, try b.term(.{ .protect = .{ .body = try b.lambda(body, body_type), .cleanup = try b.lambda(finalizer, cleanup_type) } }));
    const start_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{generator.capability}, .result = c.unit, .effects = &.{ release, generator.effect }, .capture_bound = &.{c.integer} } } });
    const main = try b.declare(&.{}, c.integer, &.{ c.read, release }, &.{});
    const answer = try b.variable(generator.answer);
    const done = try b.variable(c.unit);
    const yielded = try b.variable(generator.yielded);
    const label = try b.variable(c.integer);
    const package = try b.variable(generator.package);
    const close = try b.bind(try b.variable(c.unit), try gen.close(b, generator, try b.reference(package)), try b.pure(try b.reference(label)));
    const unpack = try b.term(.{ .unpack_product = .{ .value = try b.reference(yielded), .variables = &.{ label, package }, .body = try b.term(.{ .yield_then = close }) } });
    const matched = try b.term(.{ .match_sum = .{ .value = try b.reference(answer), .cases = &.{ .{ .variable = done, .body = try b.term(.{ .fail = try b.constant(void, {}) }) }, .{ .variable = yielded, .body = unpack } } } });
    try b.define(main, try b.bind(value, try b.term(.{ .call = .{ .function = compute, .arguments = &.{} } }), try b.bind(answer, try b.term(.{ .handle = .{ .handler = generator.handler, .body = try b.lambda(start, start_type) } }), matched)));
    return .{ .entry = main, .interface = .{
        .imports = try b.allocator().dupe(data.component.Symbol, &.{ symbol("compute", .function, compute), symbol("read", .effect, c.read) }),
        .borrows = try b.allocator().dupe(data.borrow_contract.Summary, &.{.{ .function = compute }}),
        .exports = try b.allocator().dupe(data.component.Symbol, &.{ symbol("main", .function, main), symbol("read", .effect, c.read), symbol("release", .effect, release) }),
    } };
}
fn doubled(b: *source.Builder, c: Common) !Built {
    const release = try b.effect(.{ .identity = "component/release", .payload = c.integer, .result = c.unit });
    const imported = try b.declare(&.{}, c.integer, &.{ c.read, release }, &.{});
    const main = try b.declare(&.{}, c.integer, &.{ c.read, release }, &.{});
    const value = try b.variable(c.integer);
    try b.define(main, try b.bind(value, try b.term(.{ .call = .{ .function = imported, .arguments = &.{} } }), try b.pure(try add(b, c.integer, try b.reference(value), try b.reference(value)))));
    return .{ .entry = main, .interface = .{
        .imports = try b.allocator().dupe(data.component.Symbol, &.{ symbol("main", .function, imported), symbol("read", .effect, c.read), symbol("release", .effect, release) }),
        .borrows = try b.allocator().dupe(data.borrow_contract.Summary, &.{.{ .function = imported }}),
        .exports = try b.allocator().dupe(data.component.Symbol, &.{symbol("main", .function, main)}),
    } };
}

fn recursive(b: *source.Builder, c: Common, even: bool) !Built {
    const boolean = try b.scalar(bool);
    const main = try b.declare(&.{c.integer}, boolean, &.{}, &.{});
    const other = try b.declare(&.{c.integer}, boolean, &.{}, &.{});
    const n = try b.reference(b.parameter(main, 0));
    const condition = try b.primitive(boolean, .equal, &.{ n, try b.constant(u64, 0) }, 0);
    const failure = try b.failureLiteral(try b.constant(void, {}));
    const decrement = try b.value(.{ .schema = c.integer, .expression = .{ .primitive = .{
        .opcode = .integer_sub,
        .operands = &.{ n, try b.constant(u64, 1) },
        .failures = &.{.{ .kind = .arithmetic_overflow, .value = failure }},
    } } });
    try b.define(main, try b.term(.{ .conditional = .{
        .condition = condition,
        .when_true = try b.pure(try b.constant(bool, even)),
        .when_false = try b.term(.{ .call = .{ .function = other, .arguments = &.{decrement} } }),
    } }));
    return .{ .entry = main, .interface = .{
        .imports = try b.allocator().dupe(data.component.Symbol, &.{symbol("other", .function, other)}),
        .borrows = try b.allocator().dupe(data.borrow_contract.Summary, &.{.{ .function = other }}),
        .exports = try b.allocator().dupe(data.component.Symbol, &.{symbol("main", .function, main)}),
    } };
}

pub const recursive_bindings = [_]data.linker.Binding{
    .{ .required = .{ .instance = "even", .symbol = "other" }, .supplied = .{ .instance = "odd", .symbol = "main" } },
    .{ .required = .{ .instance = "odd", .symbol = "other" }, .supplied = .{ .instance = "even", .symbol = "main" } },
};

pub const bindings = [_]data.linker.Binding{
    .{ .required = .{ .instance = "call", .symbol = "read" }, .supplied = .{ .instance = "state", .symbol = "read" } },
    .{ .required = .{ .instance = "state", .symbol = "twice" }, .supplied = .{ .instance = "call", .symbol = "twice" } },
    .{ .required = .{ .instance = "suspend", .symbol = "compute" }, .supplied = .{ .instance = "state", .symbol = "compute" } },
    .{ .required = .{ .instance = "suspend", .symbol = "read" }, .supplied = .{ .instance = "state", .symbol = "read" } },
};
pub const double_bindings = bindings ++ [_]data.linker.Binding{
    .{ .required = .{ .instance = "double", .symbol = "main" }, .supplied = .{ .instance = "suspend", .symbol = "main" } },
    .{ .required = .{ .instance = "double", .symbol = "read" }, .supplied = .{ .instance = "suspend", .symbol = "read" } },
    .{ .required = .{ .instance = "double", .symbol = "release" }, .supplied = .{ .instance = "suspend", .symbol = "release" } },
};
