//! Compile a typed residual effect into portable data; no evaluator is linked.
const std = @import("std");
const boundary = @import("boundary");

pub const Application = struct {
    pub fn emit(b: *boundary.computation.Builder) !boundary.computation.Module {
        var author = try boundary.author.Session.init(b);
        defer author.deinit();
        const integer = try author.scalar(u32);
        const unit = try author.scalar(void);
        const lookup = try author.external("example.lookup.v2", integer, integer);
        const entry = try author.declare(&.{.{ .name = "input", .schema = integer }}, integer, &.{lookup});
        var body = try author.body(entry);
        const answer = try body.bind(try body.perform(lookup, try body.parameter("input")));
        try body.finishFunction(answer);
        return author.module(entry, unit);
    }
};

pub fn main(init: std.process.Init) !void {
    var compiled = try boundary.program.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    // A compiler-only consumer can decode, inspect and admit the emitted image.
    var decoded = try boundary.data.program_image.decode(init.gpa, bytes);
    defer decoded.deinit();
    var checked = try boundary.data.activation_ownership.analyze(init.gpa, decoded.program);
    defer checked.deinit();
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
