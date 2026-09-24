//! An answer-changing deep handler can resume non-tail work or bypass it.
const std = @import("std");
const boundary = @import("boundary");

pub const Application = struct {
    pub fn emit(a: *boundary.authoring.Builder) !boundary.authoring.Module {
        const integer = try a.scalar(u64);
        const boolean = try a.scalar(bool);
        const unit = try a.scalar(void);
        const probe = try a.external("authoring/probe", integer, unit);
        const question = try a.local("authoring/question", integer, integer, .affine);
        const capability = try a.capability(question);
        const fault = try a.literalFailure(void, {});
        const h = try a.interpret(.{
            .operation = question,
            .input = integer,
            .answer = integer,
            .mode = .deep,
            .use = .affine,
            .residual = &.{probe},
            .return_effects = &.{},
            .capture_bound = &.{ integer, boolean, unit, capability },
            .state = &.{.{ .name = "bypass", .schema = boolean }},
        });
        var returns = try a.body(h.returns);
        const transformed = try returns.checkedAdd(try returns.parameter("value"), try a.literal(u64, 100), fault);
        try a.define(h.returns, try returns.finish(transformed));

        var clause = try a.body(h.clause);
        var yes = try clause.child("bypass caller");
        const bypassed = try yes.finish(try a.literal(u64, 99));
        var no = try clause.child("resume caller");
        const resumed = try no.resumeValue(try clause.parameter("resume"), try clause.parameter("payload"));
        const after = try no.checkedAdd(resumed, try a.literal(u64, 7), fault);
        const selected = try clause.select(try clause.parameter("bypass"), bypassed, try no.finish(after));
        try a.define(h.clause, try clause.finish(selected));

        const work = try a.declare("non-tail work", &.{
            .{ .name = "question", .schema = capability },
        }, integer, &.{ probe, question });
        var work_body = try a.body(work);
        _ = try work_body.perform(probe, try a.literal(u64, 1));
        const answer = try work_body.performLocal(question, try work_body.parameter("question"), try a.literal(u64, 5));
        _ = try work_body.perform(probe, try a.literal(u64, 2));
        const value = try work_body.checkedAdd(answer, try a.literal(u64, 1), fault);
        try a.define(work, try work_body.finish(value));

        const entry = try a.declare("main", &.{.{ .name = "bypass", .schema = boolean }}, integer, &.{probe});
        var body = try a.body(entry);
        const callable = try body.lambda(work, &.{}, .reusable);
        const result = try body.handle(h, callable, &.{}, &.{try body.parameter("bypass")});
        try a.define(entry, try body.finish(result));
        return a.module(entry, unit);
    }
};

pub fn main(init: std.process.Init) !void {
    var compiled = try boundary.authoring.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
