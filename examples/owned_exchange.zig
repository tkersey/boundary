//! Local disposal returns to its caller while an unrelated endpoint remains live.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.source;
const a = boundary.authoring;
const generator = boundary.library.generator;
const Build = struct {
    c: *a.Context,
    g: *const generator.Exchange,
    integer: *const a.Schema,
    unit: *const a.Schema,
    activity_payload: *const a.Schema,
    release: *const a.Operation,
    activity: *const a.Operation,
    fn add(e: @This(), body: *a.Body, value: *const a.Value, n: u64) !*const a.Value {
        return body.checkedAdd(value, try body.constant(u64, n), try e.c.literalFailure(void, {}));
    }
    fn producer(e: @This()) !*const a.Function {
        const c = e.c;
        const signature = try c.handledSchema(e.g.handler());
        const f = try c.functionFor("owned producer", signature);
        const body = try c.body(f);
        const capability = try body.parameter("capability");
        const input = try body.parameter("input");
        const work_type = try c.callable(&.{}, e.integer, &.{ e.activity, e.g.effect() }, .{ .use = .reusable, .captures = &.{ e.integer, e.g.capability() } });
        const work = try c.functionFor("exchange work", work_type);
        const working = try body.closureBody(work);
        const first = try working.performLocal(e.g.effect(), capability, input);
        _ = try working.perform(e.activity, try working.product(e.activity_payload, &.{ .{ .name = "initial", .value = input }, .{ .name = "reply", .value = first } }));
        const second = try working.performLocal(e.g.effect(), capability, try e.add(working, first, 10));
        try c.define(work, try working.ret(try e.add(working, second, 100)));
        const cleanup_type = try c.callable(&.{.{ .name = "exit", .schema = try c.cleanupInfo(e.unit) }}, e.unit, &.{e.release}, .{ .use = .reusable, .captures = &.{e.integer} });
        const cleanup = try c.functionFor("exchange cleanup", cleanup_type);
        const cleaning = try body.closureBody(cleanup);
        try c.define(cleanup, try cleaning.ret(try cleaning.perform(e.release, input)));
        try c.define(f, try body.ret(try body.protect(try body.lambda(work, work_type), try body.lambda(cleanup, cleanup_type), &.{})));
        return f;
    }
    const CheckedAnswer = struct {
        e: Build,
        parent: *a.Body,
        answer: *const a.Value,
        unexpected: *const a.Case,
        selected: *const a.Case,
        condition: *const a.Value,
        work: *a.Body,
        rejected: *a.Body,
        future: ?*const a.Value = null,
        fn finish(self: @This(), value: *const a.Value) !*const a.Value {
            const result = try self.selected.body().conditional(self.condition, try self.work.ret(value), try self.rejected.fail(self.e.integer, try self.rejected.constant(void, {})));
            return self.parent.match(self.answer, &.{ try self.unexpected.fail(self.e.integer, try self.unexpected.body().constant(void, {})), try self.selected.ret(result) });
        }
    };
    fn yielded(e: @This(), body: *a.Body, answer: *const a.Value, wanted: u64) !CheckedAnswer {
        const done = try body.caseOf(answer, "done");
        const offered = try body.caseOf(answer, "yielded");
        const parts = try offered.body().destructure(offered.payload());
        const future = try parts.get("future");
        const condition = try offered.body().equal(try parts.get("value"), try offered.body().constant(u64, wanted));
        const valid = try offered.body().branch();
        const invalid = try offered.body().branch();
        _ = try invalid.disposePackage(future);
        return .{ .e = e, .parent = body, .answer = answer, .unexpected = done, .selected = offered, .condition = condition, .work = valid, .rejected = invalid, .future = future };
    }
    fn completed(e: @This(), body: *a.Body, answer: *const a.Value, wanted: u64) !CheckedAnswer {
        const done = try body.caseOf(answer, "done");
        const offered = try body.caseOf(answer, "yielded");
        const parts = try offered.body().destructure(offered.payload());
        _ = try offered.body().disposePackage(try parts.get("future"));
        const condition = try done.body().equal(done.payload(), try done.body().constant(u64, wanted));
        return .{ .e = e, .parent = body, .answer = answer, .unexpected = offered, .selected = done, .condition = condition, .work = try done.body().branch(), .rejected = try done.body().branch() };
    }
};
const Application = struct {
    var normal = false;
    var duplicate = false;
    pub fn emit(b: *source.Builder) !source.Module {
        const c = try a.Context.init(b);
        const unit = try c.scalar(void);
        const integer = try c.scalar(u64);
        const payload = try c.record(&.{ .{ .name = "initial", .schema = integer }, .{ .name = "reply", .schema = integer } });
        const release = try c.external("owned-exchange/release", integer, unit);
        const activity = try c.external("owned-exchange/work", payload, unit);
        const g = try generator.create(c, "owned-exchange/offer", integer, integer, integer, .{
            .captures = .{ .continuation = &.{ unit, integer } },
            .residual = &.{ release, activity },
            .parameters = &.{.{ .name = "input", .schema = integer }},
            .body_use = .reusable,
        });
        const e = Build{ .c = c, .g = g, .integer = integer, .unit = unit, .activity_payload = payload, .release = release, .activity = activity };
        const producer = try e.producer();
        const entry = try c.function("entry", &.{}, integer, &.{ release, activity });
        const body = try c.body(entry);
        const callable = try body.lambda(producer, try c.handledSchema(g.handler()));
        const local = try e.yielded(body, try body.handleWithArguments(g.handler(), callable, &.{.{ .name = "input", .value = try body.constant(u64, 5) }}, &.{}), 5);
        const side = try e.yielded(local.work, try local.work.handleWithArguments(g.handler(), callable, &.{.{ .name = "input", .value = try local.work.constant(u64, 50) }}, &.{}), 50);
        var work = side.work;
        var advanced: ?Build.CheckedAnswer = null;
        var finished: ?Build.CheckedAnswer = null;
        if (normal) {
            advanced = try e.yielded(work, try work.resumePackage(local.future.?, try work.constant(u64, 7)), 17);
            work = advanced.?.work;
            finished = try e.completed(work, try work.resumePackage(advanced.?.future.?, try work.constant(u64, 9)), 109);
            work = finished.?.work;
        } else {
            _ = try work.disposePackage(local.future.?);
            if (duplicate) _ = try work.disposePackage(local.future.?);
        }
        const next_side = try e.yielded(work, try work.resumePackage(side.future.?, try work.constant(u64, 7)), 17);
        _ = try next_side.work.disposePackage(next_side.future.?);
        var result = try next_side.finish(try next_side.work.constant(u64, 42));
        if (finished) |done| result = try done.finish(result);
        if (advanced) |next| result = try next.finish(result);
        try c.define(entry, try body.ret(try local.finish(try side.finish(result))));
        return c.module(entry, unit);
    }
};
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
