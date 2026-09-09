const std = @import("std");
const boundary = @import("boundary");
const options = @import("economy_options");

pub fn main(init: std.process.Init) !void {
    var builder = boundary.computation.Builder.init(init.gpa);
    defer builder.deinit();
    const module = if (options.installations == 0) try boundary.source.examples.blobCapture(&builder) else try boundary.source.examples.installations(&builder, options.installations);
    var compiled = try boundary.program.compile(init.gpa, module);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.image_v2.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
