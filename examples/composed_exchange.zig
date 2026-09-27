//! Three owned exchanges compose through the same input/output/package interface.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.source;
const a = boundary.authoring;
const generator = boundary.library.generator;
const E = struct {
    c: *a.Context,
    integer: *const a.Schema,
    unit: *const a.Schema,
    observe: *const a.Operation,
    release: *const a.Operation,
    fn add(e: E, body: *a.Body, value: *const a.Value, increment: u64) !*const a.Value {
        return body.checkedAdd(value, try body.constant(u64, increment), try e.c.literalFailure(void, {}));
    }
    fn participant(e: E, g: *const generator.Exchange, identity: u64, increment: u64, observe: bool) !*const a.Function {
        const c = e.c;
        const loop_fn = try c.function("participant loop", &.{ .{ .name = "capability", .schema = g.capability() }, .{ .name = "input", .schema = e.integer } }, e.integer, &.{ e.observe, g.effect() });
        const loop = try c.body(loop_fn);
        const input = try loop.parameter("input");
        const capability = try loop.parameter("capability");
        const done = try loop.branch();
        const step = try loop.branch();
        const seen = if (observe) try step.perform(e.observe, input) else input;
        const next = try step.performLocal(g.effect(), capability, try e.add(step, seen, increment));
        const recur = try step.call(loop_fn, &.{ .{ .name = "capability", .value = capability }, .{ .name = "input", .value = next } });
        const zero = try loop.equal(input, try loop.constant(u64, if (Application.right_finish and identity == 2) 5 else 0));
        try c.define(loop_fn, try loop.ret(try loop.conditional(zero, try done.ret(try done.constant(u64, identity)), try step.ret(recur))));
        const body_type = try c.handledSchema(g.handler());
        const body_fn = try c.functionFor("participant", body_type);
        const body = try c.body(body_fn);
        const cap = try body.parameter("capability");
        const initial = try body.parameter("input");
        const work_type = try c.callable(&.{}, e.integer, &.{ e.observe, g.effect() }, .{ .use = .reusable, .captures = &.{ g.capability(), e.integer } });
        const work_fn = try c.functionFor("protected participant", work_type);
        const work = try body.closureBody(work_fn);
        const first = try work.performLocal(g.effect(), cap, initial);
        try c.define(work_fn, try work.ret(try work.call(loop_fn, &.{ .{ .name = "capability", .value = cap }, .{ .name = "input", .value = first } })));
        const cleanup_type = try c.callable(&.{.{ .name = "exit", .schema = try c.cleanupInfo(e.unit) }}, e.unit, &.{e.release}, .{ .use = .reusable, .captures = &.{} });
        const cleanup_fn = try c.functionFor("release participant", cleanup_type);
        const cleanup = try c.body(cleanup_fn);
        try c.define(cleanup_fn, try cleanup.ret(try cleanup.perform(e.release, try cleanup.constant(u64, identity))));
        try c.define(body_fn, try body.ret(try body.protect(try body.lambda(work_fn, work_type), try body.lambda(cleanup_fn, cleanup_type), &.{})));
        return body_fn;
    }
    const Check = struct {
        e: E,
        parent: *a.Body,
        answer: *const a.Value,
        selected: *const a.Case,
        unexpected: *const a.Case,
        condition: *const a.Value,
        work: *a.Body,
        rejected: *a.Body,
        fn finish(self: @This(), result: *const a.Value) !*const a.Value {
            const checked = try self.selected.body().conditional(self.condition, try self.work.ret(result), try self.rejected.fail(self.e.integer, try self.rejected.constant(void, {})));
            return self.parent.match(self.answer, &.{ try self.unexpected.fail(self.e.integer, try self.unexpected.body().constant(void, {})), try self.selected.ret(checked) });
        }
    };
    fn expect(e: E, work: **a.Body, checks: *std.ArrayList(Check), answer: *const a.Value, expected: u64, yielded: bool) !*const a.Value {
        const parent = work.*;
        const done = try parent.caseOf(answer, "done");
        const offered = try parent.caseOf(answer, "yielded");
        const parts = try offered.body().destructure(offered.payload());
        const package = try parts.get("future");
        const selected = if (yielded) offered else done;
        const actual = if (yielded) try parts.get("value") else done.payload();
        const condition = try selected.body().equal(actual, try selected.body().constant(u64, expected));
        const valid = try selected.body().branch();
        const invalid = try selected.body().branch();
        _ = try (if (yielded) invalid else offered.body()).disposePackage(package);
        try checks.append(a.interop.builder(e.c).allocator(), .{ .e = e, .parent = parent, .answer = answer, .selected = selected, .unexpected = if (yielded) done else offered, .condition = condition, .work = valid, .rejected = invalid });
        work.* = valid;
        return if (yielded) package else done.payload();
    }
    fn start(e: E, work: *a.Body, g: *const generator.Exchange, identity: u64, increment: u64, observe: bool) !*const a.Value {
        return work.handleWithArguments(g.handler(), try work.lambda(try e.participant(g, identity, increment, observe), try e.c.handledSchema(g.handler())), &.{.{ .name = "input", .value = try work.constant(u64, 0) }}, &.{});
    }
};
const Application = struct {
    var finish = false;
    var duplicate = false;
    var right_finish = false;
    pub fn emit(b: *source.Builder) !source.Module {
        const c = try a.Context.init(b);
        const unit = try c.scalar(void);
        const integer = try c.scalar(u64);
        const observe = try c.external("pipe/observe", integer, integer);
        const release = try c.external("pipe/release", integer, unit);
        const e = E{ .c = c, .integer = integer, .unit = unit, .observe = observe, .release = release };
        const options: generator.Options = .{ .captures = .{ .continuation = &.{ integer, unit } }, .residual = &.{ observe, release }, .parameters = &.{.{ .name = "input", .schema = integer }}, .body_use = .reusable };
        const left = try generator.create(c, "pipe/a", integer, integer, integer, options);
        const middle = try generator.create(c, "pipe/b", integer, integer, integer, options);
        const right = try generator.create(c, "pipe/c", integer, integer, integer, options);
        const pair = try generator.pipeline(c, "pipe/ab", left, middle);
        const triple = try generator.pipeline(c, "pipe/abc", pair.generator, right);
        const entry = try c.function("entry", &.{}, integer, &.{ observe, release });
        const root = try c.body(entry);
        var work = root;
        var checks: std.ArrayList(E.Check) = .empty;
        defer checks.deinit(b.allocator());
        const lp = try e.expect(&work, &checks, try e.start(work, left, 1, 1, false), 0, true);
        const mp = try e.expect(&work, &checks, try e.start(work, middle, 2, 10, true), 0, true);
        const rp = try e.expect(&work, &checks, try e.start(work, right, 3, 100, false), 0, true);
        const sibling = try e.expect(&work, &checks, try e.start(work, right, 4, 1000, true), 0, true);
        const pp = try e.expect(&work, &checks, try work.call(pair.start, &.{ .{ .name = "left", .value = lp }, .{ .name = "right", .value = mp }, .{ .name = "input", .value = try work.constant(u64, 3) } }), 18, true);
        const answer = try work.call(triple.start, &.{ .{ .name = "left", .value = pp }, .{ .name = "right", .value = rp }, .{ .name = "input", .value = try work.constant(u64, 4) } });
        if (right_finish) {
            _ = try e.expect(&work, &checks, answer, 2, false);
        } else {
            const all = try e.expect(&work, &checks, answer, 120, true);
            const next = try e.expect(&work, &checks, try work.resumePackage(all, try work.constant(u64, 5)), 122, true);
            if (finish) {
                _ = try e.expect(&work, &checks, try work.resumePackage(next, try work.constant(u64, 0)), 1, false);
            } else {
                _ = try work.disposePackage(next);
                if (duplicate) _ = try work.disposePackage(next);
            }
        }
        const last = try e.expect(&work, &checks, try work.resumePackage(sibling, try work.constant(u64, 7)), 1014, true);
        _ = try work.disposePackage(last);
        var result = try work.constant(u64, 42);
        var remaining = checks.items.len;
        while (remaining != 0) {
            remaining -= 1;
            result = try checks.items[remaining].finish(result);
        }
        try c.define(entry, try root.ret(result));
        return c.module(entry, unit);
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
