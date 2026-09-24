//! A named scoped operation body is authored, interpreted, and demanded later.
const std = @import("std");
const boundary = @import("boundary");
const a = boundary.authoring;

pub const Application = struct {
    pub fn emit(author: *a.Builder) !a.Module {
        const integer = try author.scalar(u64);
        const unit = try author.scalar(void);
        const nested = try author.declare("scoped body", &.{}, integer, &.{});
        var nested_body = try author.body(nested);
        try author.define(nested, try nested_body.finish(try author.literal(u64, 42)));
        const nested_type = try author.callableSchema(nested, &.{}, .reusable);
        const operation = try author.scopedLocal("authoring/scoped", unit, integer, &.{.{ .name = "body", .schema = nested_type }}, &.{}, .linear);
        const capability = try author.capability(operation);
        const interpretation = try author.interpret(.{
            .operation = operation,
            .input = integer,
            .answer = integer,
            .mode = .deep,
            .use = .linear,
            .capture_bound = &.{ integer, unit, nested_type, capability },
        });
        var returns = try author.body(interpretation.returns);
        try author.define(interpretation.returns, try returns.finish(try returns.parameter("value")));
        var clause = try author.body(interpretation.clause);
        const demanded = try clause.apply(try clause.asCallable(try clause.parameter("body")), &.{});
        const resumed = try clause.resumeValue(try clause.parameter("resume"), demanded);
        try author.define(interpretation.clause, try clause.finish(resumed));

        const work = try author.declare("work", &.{
            .{ .name = "capability", .schema = capability },
        }, integer, &.{operation});
        var work_body = try author.body(work);
        const nested_value = try work_body.lambda(nested, &.{}, .reusable);
        const value = try work_body.performScoped(operation, try work_body.parameter("capability"), try author.literal(void, {}), &.{nested_value}, &.{});
        try author.define(work, try work_body.finish(value));

        const entry = try author.declare("main", &.{}, integer, &.{});
        var body = try author.body(entry);
        const result = try body.handle(interpretation, try body.lambda(work, &.{}, .reusable), &.{}, &.{});
        try author.define(entry, try body.finish(result));
        return author.module(entry, unit);
    }
};

pub fn main(init: std.process.Init) !void {
    var compiled = try a.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
