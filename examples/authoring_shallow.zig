//! A shallow handler reattaches with successor state at each resumption.
const std = @import("std");
const boundary = @import("boundary");

pub const Application = struct {
    pub fn emit(a: *boundary.authoring.Builder) !boundary.authoring.Module {
        const boolean = try a.scalar(bool);
        const unit = try a.scalar(void);
        const operation = try a.local("authoring/shallow", boolean, boolean, .linear);
        const capability = try a.capability(operation);
        const interpretation = try a.interpret(.{
            .operation = operation,
            .input = boolean,
            .answer = boolean,
            .mode = .shallow,
            .use = .linear,
            .resumption_effects = &.{operation},
            .capture_bound = &.{ boolean, capability },
            .state = &.{.{ .name = "phase", .schema = boolean }},
        });
        var returns = try a.body(interpretation.returns);
        try a.define(interpretation.returns, try returns.finish(try returns.parameter("value")));
        var clause = try a.body(interpretation.clause);
        const phase = try clause.parameter("phase");
        const payload = try clause.parameter("payload");
        const valid = try clause.equal(phase, payload);
        var yes = try clause.child("matching phase");
        const resumed = try yes.resumeWith(try clause.parameter("resume"), payload, interpretation, &.{try yes.booleanNot(phase)});
        var no = try clause.child("mismatched phase");
        const answer = try clause.select(valid, try yes.finish(resumed), try no.fail(try a.literal(void, {}), boolean));
        try a.define(interpretation.clause, try clause.finish(answer));

        const work = try a.declare("work", &.{
            .{ .name = "capability", .schema = capability },
            .{ .name = "input", .schema = boolean },
        }, boolean, &.{operation});
        var work_body = try a.body(work);
        const cap = try work_body.parameter("capability");
        _ = try work_body.performLocal(operation, cap, try work_body.parameter("input"));
        const second = try work_body.performLocal(operation, cap, try a.literal(bool, true));
        try a.define(work, try work_body.finish(second));

        const entry = try a.declare("main", &.{.{ .name = "input", .schema = boolean }}, boolean, &.{});
        var body = try a.body(entry);
        const callable = try body.lambda(work, &.{}, .reusable);
        const handled = try body.handle(interpretation, callable, &.{try body.parameter("input")}, &.{try a.literal(bool, false)});
        try a.define(entry, try body.finish(handled));
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
