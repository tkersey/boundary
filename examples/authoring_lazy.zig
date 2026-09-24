//! Both delayed bodies are authored; only the selected one runs under World.
const std = @import("std");
const boundary = @import("boundary");

pub const Application = struct {
    pub fn emit(a: *boundary.authoring.Builder) !boundary.authoring.Module {
        const integer = try a.scalar(u64);
        const boolean = try a.scalar(bool);
        const unit = try a.scalar(void);
        const failing = try a.declare("failing delayed work", &.{}, integer, &.{});
        var failure_body = try a.body(failing);
        try a.define(failing, try failure_body.fail(try a.literal(void, {}), integer));
        const succeeding = try a.declare("successful delayed work", &.{}, integer, &.{});
        var success_body = try a.body(succeeding);
        try a.define(succeeding, try success_body.finish(try a.literal(u64, 42)));
        const entry = try a.declare("main", &.{.{ .name = "demand_failure", .schema = boolean }}, integer, &.{});
        var body = try a.body(entry);
        var yes = try body.child("demand failing body");
        const failure = try yes.apply(try yes.lambda(failing, &.{}, .reusable), &.{});
        var no = try body.child("demand successful body");
        const success = try no.apply(try no.lambda(succeeding, &.{}, .reusable), &.{});
        const selected = try body.select(try body.parameter("demand_failure"), try yes.finish(failure), try no.finish(success));
        try a.define(entry, try body.finish(selected));
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
