//! Clone-safe hyperfunction descriptions, private branch mutation and shared state.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const hyper = boundary.library.hyper;
const choice = boundary.library.choice;
const Id = source.Id;
fn add(b: *source.Builder, x: Id, y: Id) !Id {
    return b.value(.{ .schema = try b.scalar(u64), .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ x, y }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
}
fn callable(b: *source.Builder, parameters: []const Id, result: Id, effects: []const Id, captures: []const Id, regions: []const Id) !Id {
    return b.schema(.{ .internal = .{ .computation = .{ .parameters = parameters, .result = result, .effects = effects, .capture_bound = captures, .regions = regions } } });
}
const Application = struct {
    var reentrant = false;
    pub fn emit(b: *source.Builder) !source.Module {
        if (reentrant) return reentry(b);
        const unit = try b.scalar(void);
        const integer = try b.scalar(u64);
        const boolean = try b.scalar(bool);
        const row = try b.schema(.{ .product = &.{ boolean, integer, integer, integer } });
        const shared = b.region();
        const local = b.region();
        const sr = try b.schema(.{ .internal = .{ .region = shared } });
        const lr = try b.schema(.{ .internal = .{ .region = local } });
        const sc = try b.schema(.{ .internal = .{ .cell = .{ .element = integer, .region = shared } } });
        const lc = try b.schema(.{ .internal = .{ .cell = .{ .element = integer, .region = local } } });
        const pair = try hyper.pair(b, integer, integer);
        const observe = try b.effect(.{ .identity = "hyper/clone-observe", .payload = row, .result = unit });
        const branch = try choice.family(b, "hyper/clone-branch");
        const all = try choice.allScoped(b, branch, row, &.{ unit, boolean, integer, row, sr, lr, sc, lc, branch.capability, pair.forward, pair.backward, pair.peer_forward, pair.peer_backward, pair.answer_forward, pair.answer_backward }, .{ .effects = &.{observe} }, &.{local}, &.{shared});
        const outer = try b.declare(&.{sr}, all.answer, &.{observe}, &.{shared});
        const shared_cell = try b.variable(sc);
        const body = try b.declare(&.{branch.capability}, row, &.{ observe, branch.effect }, &.{shared});
        const inner = try b.declare(&.{lr}, row, &.{ observe, branch.effect }, &.{ shared, local });
        const local_cell = try b.variable(lc);
        const seed = try b.variable(integer);
        const transform = try b.declare(&.{pair.answer_backward}, pair.answer_forward, &.{}, &.{});
        const delay = try b.declare(&.{}, integer, &.{}, &.{});
        const argument = try b.variable(integer);
        try b.define(delay, try b.bind(argument, try hyper.force(b, try b.reference(b.parameter(transform, 0))), try b.pure(try add(b, try b.reference(argument), try b.reference(seed)))));
        try b.define(transform, try b.pure(try b.lambda(delay, pair.answer_forward)));
        const participant = try b.variable(pair.forward);
        const selected = try b.variable(boolean);
        const left = try b.variable(integer);
        const right = try b.variable(integer);
        const delayed = try b.variable(pair.answer_forward);
        const answer = try b.variable(integer);
        const result = try b.primitive(row, .product, &.{ try b.reference(selected), try b.reference(left), try b.reference(right), try b.reference(answer) }, 0);
        const finished = try b.bind(try b.variable(unit), try b.term(.{ .perform = .{ .effect = observe, .payload = result } }), try b.pure(result));
        const input = try hyper.deferValue(b, pair.answer_backward, try add(b, try b.reference(left), try b.reference(right)));
        const projected = try b.bind(delayed, try hyper.project(b, pair, try b.reference(participant), input), try b.bind(answer, try hyper.force(b, try b.reference(delayed)), finished));
        const read_local = try b.primitive(integer, .cell_get, &.{try b.reference(local_cell)}, 0);
        const read_shared = try b.primitive(integer, .cell_get, &.{try b.reference(shared_cell)}, 0);
        const update_local = try b.pure(try b.primitive(unit, .cell_set, &.{ try b.reference(local_cell), try add(b, read_local, try b.constant(u64, 1)) }, 0));
        const update_shared = try b.pure(try b.primitive(unit, .cell_set, &.{ try b.reference(shared_cell), try add(b, read_shared, try b.constant(u64, 1)) }, 0));
        const read_back = try b.bind(left, try b.pure(read_local), try b.bind(right, try b.pure(read_shared), projected));
        const mutation = try b.bind(try b.variable(unit), update_local, try b.bind(try b.variable(unit), update_shared, read_back));
        const capture = try b.term(.{ .perform = .{ .effect = branch.effect, .capability = try b.reference(b.parameter(body, 0)), .payload = try b.constant(void, {}) } });
        const start = try b.bind(participant, try hyper.lift(b, pair, transform), try b.bind(selected, capture, mutation));
        const allocated = try b.pure(try b.primitive(lc, .cell_new, &.{ try b.reference(b.parameter(inner, 0)), try b.constant(u64, 0) }, 0));
        try b.define(inner, try b.bind(local_cell, allocated, try b.bind(seed, try b.pure(try b.constant(u64, 37)), start)));
        try b.define(body, try b.term(.{ .with_region = .{ .region = local, .body = try b.lambda(inner, try callable(b, &.{lr}, row, &.{ observe, branch.effect }, &.{ sc, branch.capability }, &.{ shared, local })) } }));
        const handled = try b.term(.{ .handle = .{ .handler = all.handler, .body = try b.lambda(body, try callable(b, &.{branch.capability}, row, &.{ observe, branch.effect }, &.{sc}, &.{shared})) } });
        try b.define(outer, try b.bind(shared_cell, try b.pure(try b.primitive(sc, .cell_new, &.{ try b.reference(b.parameter(outer, 0)), try b.constant(u64, 0) }, 0)), handled));
        const entry = try b.declare(&.{}, all.answer, &.{observe}, &.{});
        try b.define(entry, try b.term(.{ .with_region = .{ .region = shared, .body = try b.lambda(outer, try callable(b, &.{sr}, all.answer, &.{observe}, &.{}, &.{shared})) } }));
        return b.module(entry, unit);
    }
};
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    if (args.next()) |mode| {
        if (!std.mem.eql(u8, mode, "reentrant") or args.next() != null) return error.InvalidMode;
        Application.reentrant = true;
    }
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

fn reentry(b: *source.Builder) !source.Module {
    const integer = try b.scalar(u64);
    const pair = try hyper.pair(b, integer, integer);
    const transform = try b.declare(&.{pair.answer_backward}, pair.answer_forward, &.{}, &.{});
    const delay = try b.declare(&.{}, integer, &.{}, &.{});
    const x = try b.variable(integer);
    try b.define(delay, try b.bind(x, try hyper.force(b, try b.reference(b.parameter(transform, 0))), try b.pure(try add(b, try b.reference(x), try b.constant(u64, 37)))));
    try b.define(transform, try b.pure(try b.lambda(delay, pair.answer_forward)));
    const compute = try b.declare(&.{}, integer, &.{}, &.{});
    const h = try b.variable(pair.forward);
    const value = try b.variable(pair.answer_forward);
    try b.define(compute, try b.bind(h, try hyper.lift(b, pair, transform), try b.bind(value, try hyper.project(b, pair, try b.reference(h), try hyper.deferValue(b, pair.answer_backward, try b.constant(u64, 5))), try hyper.force(b, try b.reference(value)))));
    return source.examples.reentrantWithResult(b, compute, true);
}
