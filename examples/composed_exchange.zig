//! Three owned exchanges compose through the same input/output/package interface.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const generator = boundary.library.generator;
const Id = source.Id;
const E = struct {
    b: *source.Builder,
    integer: Id,
    unit: Id,
    observe: Id,
    release: Id,
    fn add(e: E, value: Id, increment: u64) !Id {
        return e.b.value(.{ .schema = e.integer, .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ value, try e.b.constant(u64, increment) }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try e.b.failureLiteral(try e.b.constant(void, {})) }} } } });
    }
    fn participant(e: E, g: generator.Generator, identity: u64, increment: u64, observe: bool) !Id {
        const b = e.b;
        const loop = try b.declare(&.{ g.capability, e.integer }, e.integer, &.{ e.observe, g.effect }, &.{});
        const input = try b.reference(b.parameter(loop, 1));
        const seen = try b.variable(e.integer);
        const next = try b.variable(e.integer);
        const offer = try b.term(.{ .perform = .{ .effect = g.effect, .capability = try b.reference(b.parameter(loop, 0)), .payload = try e.add(try b.reference(seen), increment) } });
        const recur = try b.term(.{ .call = .{ .function = loop, .arguments = &.{ try b.reference(b.parameter(loop, 0)), try b.reference(next) } } });
        const read = if (observe) try b.term(.{ .perform = .{ .effect = e.observe, .payload = input } }) else try b.pure(input);
        const work = try b.bind(seen, read, try b.bind(next, offer, recur));
        const zero = try b.primitive(try b.scalar(bool), .equal, &.{ input, try b.constant(u64, if (Application.right_finish and identity == 2) 5 else 0) }, 0);
        try b.define(loop, try b.term(.{ .conditional = .{ .condition = zero, .when_true = try b.pure(try b.constant(u64, identity)), .when_false = work } }));
        const body = try b.declare(&.{ g.capability, e.integer }, e.integer, &.{ e.observe, e.release, g.effect }, &.{});
        const run = try b.declare(&.{}, e.integer, &.{ e.observe, g.effect }, &.{});
        const first = try b.variable(e.integer);
        const ready = try b.term(.{ .perform = .{ .effect = g.effect, .capability = try b.reference(b.parameter(body, 0)), .payload = try b.reference(b.parameter(body, 1)) } });
        try b.define(run, try b.bind(first, ready, try b.term(.{ .call = .{ .function = loop, .arguments = &.{ try b.reference(b.parameter(body, 0)), try b.reference(first) } } })));
        const exit = try boundary.library.cleanup.exitInfo(b, e.unit);
        const cleanup = try b.declare(&.{exit}, e.unit, &.{e.release}, &.{});
        try b.define(cleanup, try b.term(.{ .perform = .{ .effect = e.release, .payload = try b.constant(u64, identity) } }));
        const rt = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{}, .result = e.integer, .effects = &.{ e.observe, g.effect }, .capture_bound = &.{ g.capability, e.integer } } } });
        const ct = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{exit}, .result = e.unit, .effects = &.{e.release} } } });
        try b.define(body, try b.term(.{ .protect = .{ .body = try b.lambda(run, rt), .cleanup = try b.lambda(cleanup, ct) } }));
        const signature = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ g.capability, e.integer }, .result = e.integer, .effects = &.{ e.observe, e.release, g.effect } } } });
        return b.lambda(body, signature);
    }
    fn yielded(e: E, g: generator.Generator, answer: Id, expected: u64, owner: Id, next: Id) !Id {
        const b = e.b;
        const pair = try b.variable(g.yielded);
        const value = try b.variable(g.element);
        const same = try b.primitive(try b.scalar(bool), .equal, &.{ try b.reference(value), try b.constant(u64, expected) }, 0);
        const failed = try b.bind(try b.variable(e.unit), try generator.close(b, g, try b.reference(owner)), try b.term(.{ .fail = try b.constant(void, {}) }));
        return b.term(.{ .match_sum = .{ .value = answer, .cases = &.{
            .{ .variable = try b.variable(g.result), .body = try b.term(.{ .fail = try b.constant(void, {}) }) },
            .{ .variable = pair, .body = try b.term(.{ .unpack_product = .{ .value = try b.reference(pair), .variables = &.{ value, owner }, .body = try b.term(.{ .conditional = .{ .condition = same, .when_true = next, .when_false = failed } }) } }) },
        } } });
    }
    fn completed(e: E, g: generator.Generator, answer: Id, expected: u64, next: Id) !Id {
        const b = e.b;
        const value = try b.variable(g.result);
        const pair = try b.variable(g.yielded);
        const payload = try b.variable(g.element);
        const owned = try b.variable(g.package);
        const fail = try b.term(.{ .fail = try b.constant(void, {}) });
        const close = try b.term(.{ .unpack_product = .{ .value = try b.reference(pair), .variables = &.{ payload, owned }, .body = try b.bind(try b.variable(e.unit), try generator.close(b, g, try b.reference(owned)), fail) } });
        const same = try b.primitive(try b.scalar(bool), .equal, &.{ try b.reference(value), try b.constant(u64, expected) }, 0);
        return b.term(.{ .match_sum = .{ .value = answer, .cases = &.{
            .{ .variable = value, .body = try b.term(.{ .conditional = .{ .condition = same, .when_true = next, .when_false = fail } }) },
            .{ .variable = pair, .body = close },
        } } });
    }
};
const Application = struct {
    var finish = false;
    var duplicate = false;
    var right_finish = false;
    pub fn emit(b: *source.Builder) !source.Module {
        const unit = try b.scalar(void);
        const integer = try b.scalar(u64);
        const observe = try b.effect(.{ .identity = "pipe/observe", .payload = integer, .result = integer });
        const release = try b.effect(.{ .identity = "pipe/release", .payload = integer, .result = unit });
        const e = E{ .b = b, .integer = integer, .unit = unit, .observe = observe, .release = release };
        const a = try generator.defineExchange(b, "pipe/a", integer, integer, integer, &.{ integer, unit }, &.{}, &.{}, .{ .effects = &.{ observe, release } });
        const z = try generator.defineExchange(b, "pipe/b", integer, integer, integer, &.{ integer, unit }, &.{}, &.{}, .{ .effects = &.{ observe, release } });
        const c = try generator.defineExchange(b, "pipe/c", integer, integer, integer, &.{ integer, unit }, &.{}, &.{}, .{ .effects = &.{ observe, release } });
        const az = try generator.compose(b, "pipe/ab", a, z);
        const azc = try generator.compose(b, "pipe/abc", az.generator, c);
        const entry = try b.declare(&.{}, integer, &.{ observe, release }, &.{});
        const aa = try b.variable(a.answer);
        const za = try b.variable(z.answer);
        const ca = try b.variable(c.answer);
        const ap = try b.variable(a.package);
        const zp = try b.variable(z.package);
        const cp = try b.variable(c.package);
        const da = try b.variable(c.answer);
        const dp = try b.variable(c.package);
        const aza = try b.variable(az.generator.answer);
        const azp = try b.variable(az.generator.package);
        const all = try b.variable(azc.generator.answer);
        const allp = try b.variable(azc.generator.package);
        const next = try b.variable(azc.generator.answer);
        const np = try b.variable(azc.generator.package);
        const sibling = try b.variable(c.answer);
        const sibling_next = try b.variable(c.package);
        const final = try b.bind(try b.variable(unit), try generator.close(b, c, try b.reference(sibling_next)), try b.pure(try b.constant(u64, 42)));
        const done = try b.bind(sibling, try generator.exchange(b, c, try b.reference(dp), try b.constant(u64, 7)), try e.yielded(c, try b.reference(sibling), 1014, sibling_next, final));
        var stop = try b.bind(try b.variable(unit), try generator.close(b, azc.generator, try b.reference(np)), done);
        if (duplicate) stop = try b.bind(try b.variable(unit), try generator.close(b, azc.generator, try b.reference(np)), stop);
        if (finish) {
            const completed = try b.variable(azc.generator.result);
            const unexpected = try b.variable(azc.generator.yielded);
            const v = try b.variable(integer);
            const p = try b.variable(azc.generator.package);
            const ended = try b.variable(azc.generator.answer);
            const good = try b.primitive(try b.scalar(bool), .equal, &.{ try b.reference(completed), try b.constant(u64, 1) }, 0);
            const dispatch = try b.term(.{ .match_sum = .{ .value = try b.reference(ended), .cases = &.{
                .{ .variable = completed, .body = try b.term(.{ .conditional = .{ .condition = good, .when_true = done, .when_false = try b.term(.{ .fail = try b.constant(void, {}) }) } }) },
                .{ .variable = unexpected, .body = try b.term(.{ .unpack_product = .{ .value = try b.reference(unexpected), .variables = &.{ v, p }, .body = try b.bind(try b.variable(unit), try generator.close(b, azc.generator, try b.reference(p)), try b.term(.{ .fail = try b.constant(void, {}) })) } }) },
            } } });
            stop = try b.bind(ended, try generator.exchange(b, azc.generator, try b.reference(np), try b.constant(u64, 0)), dispatch);
        }
        const second = try b.bind(next, try generator.exchange(b, azc.generator, try b.reference(allp), try b.constant(u64, 5)), try e.yielded(azc.generator, try b.reference(next), 122, np, stop));
        const joined = try b.bind(all, try b.term(.{ .call = .{ .function = azc.start, .arguments = &.{ try b.reference(azp), try b.reference(cp), try b.constant(u64, 4) } } }), if (right_finish) try e.completed(azc.generator, try b.reference(all), 2, done) else try e.yielded(azc.generator, try b.reference(all), 120, allp, second));
        const first = try b.bind(aza, try b.term(.{ .call = .{ .function = az.start, .arguments = &.{ try b.reference(ap), try b.reference(zp), try b.constant(u64, 3) } } }), try e.yielded(az.generator, try b.reference(aza), 18, azp, joined));
        const retained = try b.bind(da, try generator.begin(b, c, try e.participant(c, 4, 1000, true), try b.constant(u64, 0)), try e.yielded(c, try b.reference(da), 0, dp, first));
        const third = try b.bind(ca, try generator.begin(b, c, try e.participant(c, 3, 100, false), try b.constant(u64, 0)), try e.yielded(c, try b.reference(ca), 0, cp, retained));
        const two = try b.bind(za, try generator.begin(b, z, try e.participant(z, 2, 10, true), try b.constant(u64, 0)), try e.yielded(z, try b.reference(za), 0, zp, third));
        try b.define(entry, try b.bind(aa, try generator.begin(b, a, try e.participant(a, 1, 1, false), try b.constant(u64, 0)), try e.yielded(a, try b.reference(aa), 0, ap, two)));
        return b.module(entry, unit);
    }
};
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    if (args.next()) |mode| {
        if (std.mem.eql(u8, mode, "finish")) Application.finish = true else if (std.mem.eql(u8, mode, "duplicate")) Application.duplicate = true else if (std.mem.eql(u8, mode, "right-finish")) Application.right_finish = true else return error.InvalidMode;
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
