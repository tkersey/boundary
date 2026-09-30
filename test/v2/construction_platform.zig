// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const boundary = @import("boundary");
const data = @import("boundary_data");
const fixture = @import("construction.zig");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.Mode;
    const salt = try std.fmt.parseInt(usize, args.next() orelse return error.Configuration, 10);
    var flags: [7]bool = undefined;
    for (&flags, 0..) |*flag, i| flag.* = (i + salt) % 3 == 0;
    var b = boundary.source.Builder.init(init.gpa);
    defer b.deinit();
    var trace: fixture.Trace = .{};
    const module = if (std.mem.eql(u8, mode, "raw")) try fixture.rawChain(&b, &flags, &trace) else if (std.mem.eql(u8, mode, "typed")) try fixture.typedChain(&b, &flags, &trace) else return error.Mode;
    var compiled = try boundary.program.compile(init.gpa, module);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try data.program_image.encode(init.gpa, compiled.program, bytes);
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try out.interface.writeAll(bytes);
    try out.interface.flush();
    var eb: [512]u8 = undefined;
    var err = std.Io.File.stderr().writer(init.io, &eb);
    try std.json.Stringify.value(trace, .{}, &err.interface);
    try err.interface.writeByte('\n');
    try err.interface.flush();
}
