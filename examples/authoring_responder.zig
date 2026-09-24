//! An authored responder interprets a local question through an external lookup.
const std = @import("std");
const boundary = @import("boundary");

pub const Application = struct {
    pub fn emit(a: *boundary.authoring.Builder) !boundary.authoring.Module {
        const integer = try a.scalar(u64);
        const question = try a.local("authoring/question", integer, integer, .linear);
        const lookup = try a.external("authoring/lookup", integer, integer);
        const capability = try a.capability(question);

        const responder = try a.declare("responder", &.{.{ .name = "key", .schema = integer }}, integer, &.{lookup});
        var responder_body = try a.body(responder);
        const reply = try responder_body.perform(lookup, try responder_body.parameter("key"));
        try a.define(responder, try responder_body.finish(reply));
        const interpretation = try a.responder(question, responder, &.{lookup}, &.{ integer, capability }, .deep, .linear);

        const work = try a.declare("work", &.{
            .{ .name = "question", .schema = capability },
            .{ .name = "key", .schema = integer },
        }, integer, &.{question});
        var work_body = try a.body(work);
        const answered = try work_body.performLocal(question, try work_body.parameter("question"), try work_body.parameter("key"));
        try a.define(work, try work_body.finish(answered));

        const entry = try a.declare("entry", &.{.{ .name = "input", .schema = integer }}, integer, &.{lookup});
        var body = try a.body(entry);
        const callable = try body.lambda(work, &.{}, .reusable);
        const result = try body.handle(interpretation, callable, &.{try body.parameter("input")}, &.{});
        try a.define(entry, try body.finish(result));
        return a.module(entry, try a.scalar(void));
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
