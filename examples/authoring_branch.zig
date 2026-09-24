//! A runtime Boolean selects one external request or a pure return.
const std = @import("std");
const boundary = @import("boundary");

pub const Application = struct {
    pub fn emit(a: *boundary.authoring.Builder) !boundary.authoring.Module {
        const boolean = try a.scalar(bool);
        const integer = try a.scalar(u32);
        const lookup = try a.external("authoring/lookup", integer, integer);
        const entry = try a.declare("main", &.{
            .{ .name = "query", .schema = boolean },
            .{ .name = "input", .schema = integer },
        }, integer, &.{lookup});
        var body = try a.body(entry);
        const query = try body.parameter("query");
        const input = try body.parameter("input");
        var yes = try body.child("external");
        const requested = try yes.perform(lookup, input);
        var no = try body.child("pure");
        const selected = try body.select(query, try yes.finish(requested), try no.finish(input));
        try a.define(entry, try body.finish(selected));
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
