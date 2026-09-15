//! Emit a compact image through the public codec, preserving ordinary authoring.
const std = @import("std");
const boundary = @import("boundary");

pub fn main(init: std.process.Init) !void {
    var builder = boundary.computation.Builder.init(init.gpa);
    defer builder.deinit();
    var compiled = try boundary.program.compile(init.gpa, try boundary.source.examples.installations(&builder, 64));
    defer compiled.deinit();
    const codec = boundary.data_v2.compact_image;
    const bytes = try init.gpa.alloc(u8, try codec.encodedLength(init.gpa, compiled.program));
    defer init.gpa.free(bytes);
    const encoded = try codec.encode(init.gpa, compiled.program, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(encoded);
    try output.interface.flush();
}
