//! Reproducible synthetic size witnesses; stdout remains a portable image.
const std = @import("std");
const boundary = @import("boundary");

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const count = try std.fmt.parseInt(usize, args.next() orelse return error.MissingCount, 10);
    const kind = args.next() orelse return error.MissingKind;
    const format = args.next() orelse return error.MissingFormat;
    if (args.next() != null or count == 0) return error.InvalidArguments;
    const mixed = std.mem.eql(u8, kind, "mixed");
    const irregular = std.mem.eql(u8, kind, "irregular");
    const constant = std.mem.eql(u8, kind, "constant");
    if (!mixed and !irregular and !constant and !std.mem.eql(u8, kind, "install"))
        return error.InvalidKind;
    const legacy = std.mem.eql(u8, format, "bpi2");
    if (!legacy and !std.mem.eql(u8, format, "bpc1")) return error.InvalidFormat;
    var builder = boundary.source.Builder.init(init.gpa);
    defer builder.deinit();
    const module = if (constant)
        try @import("compact_fixtures.zig").storedConstant(&builder, std.math.mul(usize, count, 1024) catch return error.InvalidLength)
    else if (irregular)
        try @import("compact_fixtures.zig").variedMixed(&builder, count, .{ .seed = 11 })
    else if (mixed)
        try @import("compact_fixtures.zig").mixed(&builder, count, 0, false)
    else
        try boundary.source.examples.installations(&builder, count);
    var compiled = try boundary.program.compile(init.gpa, module);
    defer compiled.deinit();
    if (constant and compiled.program.constants.len != 1) return error.DuplicatedConstant;
    const size = if (legacy)
        try boundary.data_v2.image.encodedLength(compiled.program)
    else
        try boundary.data_v2.compact_image.encodedLength(init.gpa, compiled.program);
    const bytes = try init.gpa.alloc(u8, size);
    defer init.gpa.free(bytes);
    if (legacy) {
        _ = try compiled.encode(init.gpa, bytes);
    } else _ = try boundary.data_v2.compact_image.encode(init.gpa, compiled.program, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
