//! Local disposal returns to its caller while an unrelated endpoint remains live.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const generator = boundary.library.generator;
const Id = source.Id;
const Build = struct {
    b: *source.Builder,
    g: generator.Generator,
    integer: Id,
    unit: Id,
    release: Id,
    activity: Id,
    fn ref(e: @This(), id: Id) !Id {
        return e.b.reference(id);
    }
    fn add(e: @This(), a: Id, n: u64) !Id {
        return e.b.value(.{ .schema = e.integer, .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ a, try e.b.constant(u64, n) }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try e.b.failureLiteral(try e.b.constant(void, {})) }} } } });
    }
    fn fail(e: @This()) !Id {
        return e.b.term(.{ .fail = try e.b.constant(void, {}) });
    }
    fn body(e: @This()) !Id {
        const b = e.b;
        const f = try b.declare(&.{ e.g.capability, e.integer }, e.integer, &.{ e.release, e.activity, e.g.effect }, &.{});
        const work = try b.declare(&.{}, e.integer, &.{ e.activity, e.g.effect }, &.{});
        const first = try b.variable(e.integer);
        const second = try b.variable(e.integer);
        const offer1 = try b.term(.{ .perform = .{ .effect = e.g.effect, .capability = try e.ref(b.parameter(f, 0)), .payload = try e.ref(b.parameter(f, 1)) } });
        const offer2 = try b.term(.{ .perform = .{ .effect = e.g.effect, .capability = try e.ref(b.parameter(f, 0)), .payload = try e.add(try e.ref(first), 10) } });
        const payload = try b.primitive(try b.schema(.{ .product = &.{ e.integer, e.integer } }), .product, &.{ try e.ref(b.parameter(f, 1)), try e.ref(first) }, 0);
        const activity = try b.term(.{ .perform = .{ .effect = e.activity, .payload = payload } });
        try b.define(work, try b.bind(first, offer1, try b.bind(try b.variable(e.unit), activity, try b.bind(second, offer2, try b.pure(try e.add(try e.ref(second), 100))))));
        const exit = try boundary.library.cleanup.exitInfo(b, e.unit);
        const cleanup = try b.declare(&.{exit}, e.unit, &.{e.release}, &.{});
        try b.define(cleanup, try b.term(.{ .perform = .{ .effect = e.release, .payload = try e.ref(b.parameter(f, 1)) } }));
        const work_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{}, .result = e.integer, .effects = &.{ e.activity, e.g.effect }, .capture_bound = &.{ e.integer, e.g.capability } } } });
        const cleanup_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{exit}, .result = e.unit, .effects = &.{e.release}, .capture_bound = &.{e.integer} } } });
        try b.define(f, try b.term(.{ .protect = .{ .body = try b.lambda(work, work_type), .cleanup = try b.lambda(cleanup, cleanup_type) } }));
        const signature = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ e.g.capability, e.integer }, .result = e.integer, .effects = &.{ e.release, e.activity, e.g.effect } } } });
        return b.lambda(f, signature);
    }
    fn yielded(e: @This(), answer: Id, wanted: u64, package: Id, next: Id) !Id {
        const b = e.b;
        const pair = try b.variable(e.g.yielded);
        const value = try b.variable(e.integer);
        const equal = try b.primitive(try b.scalar(bool), .equal, &.{ try e.ref(value), try b.constant(u64, wanted) }, 0);
        const dropped = try b.bind(try b.variable(e.unit), try generator.close(b, e.g, try e.ref(package)), try e.fail());
        const guarded = try b.term(.{ .conditional = .{ .condition = equal, .when_true = next, .when_false = dropped } });
        const unpack = try b.term(.{ .unpack_product = .{ .value = try e.ref(pair), .variables = &.{ value, package }, .body = guarded } });
        return b.term(.{ .match_sum = .{ .value = answer, .cases = &.{
            .{ .variable = try b.variable(e.integer), .body = try e.fail() }, .{ .variable = pair, .body = unpack },
        } } });
    }
};
const Application = struct {
    var normal = false;
    var duplicate = false;
    pub fn emit(b: *source.Builder) !source.Module {
        const unit = try b.scalar(void);
        const integer = try b.scalar(u64);
        const release = try b.effect(.{ .identity = "owned-exchange/release", .payload = integer, .result = unit });
        const activity = try b.effect(.{ .identity = "owned-exchange/work", .payload = try b.schema(.{ .product = &.{ integer, integer } }), .result = unit });
        const g = try generator.defineExchange(b, "owned-exchange/offer", integer, integer, integer, &.{ unit, integer }, &.{}, &.{}, .{ .effects = &.{ release, activity } });
        const e = Build{ .b = b, .g = g, .integer = integer, .unit = unit, .release = release, .activity = activity };
        const body = try e.body();
        const entry = try b.declare(&.{}, integer, &.{ release, activity }, &.{});
        const a = try b.variable(g.answer);
        const z = try b.variable(g.answer);
        const ap = try b.variable(g.package);
        const zp = try b.variable(g.package);
        const next = try b.variable(g.answer);
        const nextp = try b.variable(g.package);
        const finish = try b.bind(try b.variable(unit), try generator.close(b, g, try e.ref(nextp)), try b.pure(try b.constant(u64, 42)));
        const after_side = try e.yielded(try e.ref(next), 17, nextp, finish);
        const resume_side = try b.bind(next, try generator.exchange(b, g, try e.ref(zp), try b.constant(u64, 7)), after_side);
        const after_dispose = if (duplicate) try b.bind(try b.variable(unit), try generator.close(b, g, try e.ref(ap)), resume_side) else resume_side;
        var dispose = try b.bind(try b.variable(unit), try generator.close(b, g, try e.ref(ap)), after_dispose);
        if (normal) dispose = try normalExchange(e, ap, resume_side);
        const side = try e.yielded(try e.ref(z), 50, zp, dispose);
        const started = try b.bind(z, try generator.begin(b, g, body, try b.constant(u64, 50)), side);
        try b.define(entry, try b.bind(a, try generator.begin(b, g, body, try b.constant(u64, 5)), try e.yielded(try e.ref(a), 5, ap, started)));
        return b.module(entry, unit);
    }
};
fn normalExchange(e: Build, package: Id, next: Id) !Id {
    const b = e.b;
    const answer = try b.variable(e.g.answer);
    const successor = try b.variable(e.g.package);
    const final = try b.variable(e.g.answer);
    const completed = try b.variable(e.integer);
    const unexpected = try b.variable(e.g.yielded);
    const v = try b.variable(e.integer);
    const owned = try b.variable(e.g.package);
    const dispose = try b.term(.{ .unpack_product = .{ .value = try e.ref(unexpected), .variables = &.{ v, owned }, .body = try b.bind(try b.variable(e.unit), try generator.close(b, e.g, try e.ref(owned)), try e.fail()) } });
    const equal = try b.primitive(try b.scalar(bool), .equal, &.{ try e.ref(completed), try b.constant(u64, 109) }, 0);
    const done = try b.term(.{ .match_sum = .{ .value = try e.ref(final), .cases = &.{
        .{ .variable = completed, .body = try b.term(.{ .conditional = .{ .condition = equal, .when_true = next, .when_false = try e.fail() } }) },
        .{ .variable = unexpected, .body = dispose },
    } } });
    const last = try b.bind(final, try generator.exchange(b, e.g, try e.ref(successor), try b.constant(u64, 9)), done);
    return b.bind(answer, try generator.exchange(b, e.g, try e.ref(package), try b.constant(u64, 7)), try e.yielded(try e.ref(answer), 17, successor, last));
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    if (args.next()) |mode| {
        if (std.mem.eql(u8, mode, "normal")) Application.normal = true else if (std.mem.eql(u8, mode, "duplicate")) Application.duplicate = true else return error.InvalidMode;
    }
    var compiled = try boundary.program.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try out.interface.writeAll(bytes);
    try out.interface.flush();
}
