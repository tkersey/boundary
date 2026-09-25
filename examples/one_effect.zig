//! Compile a typed residual effect into portable data; no evaluator is linked.
const std = @import("std");
const boundary = @import("boundary");

pub const Application = struct {
    pub fn emit(b: *boundary.computation.Builder) !boundary.computation.Module {
        const c = try boundary.authoring.Context.init(b);
        const integer = try c.scalar(u32);
        const lookup = try c.external("example.lookup.v2", integer, integer);
        const entry = try c.function("lookup", &.{.{ .name = "key", .schema = integer }}, integer, &.{lookup});
        const body = try c.body(entry);
        const answer = try body.perform(lookup, try body.parameter("key"));
        try c.define(entry, try body.ret(answer));
        return c.module(entry, try c.scalar(void));
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
