const std = @import("std");
const boundary = @import("boundary");

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const count = try std.fmt.parseInt(usize, args.next() orelse return error.MissingCount, 10);
    if (args.next() != null) return error.InvalidArguments;
    switch (count) {
        0, 1, 8, 64 => {},
        else => return error.InvalidCount,
    }
    var builder = boundary.source.Builder.init(init.gpa);
    defer builder.deinit();
    const module = if (count == 0) try boundary.source.examples.blobCapture(&builder) else try boundary.source.examples.installations(&builder, count);
    var compiled = try boundary.program.compile(init.gpa, module);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
