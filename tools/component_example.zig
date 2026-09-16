// Copyright (c) 2026 Boundary contributors. MIT license.
//! Each invocation authors and compiles exactly one relocatable object.
const std = @import("std");
const boundary = @import("boundary");

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const name = args.next() orelse return error.MissingComponent;
    if (args.next() != null) return error.UnexpectedArgument;
    const kind = std.meta.stringToEnum(boundary.source.component_examples.Kind, name) orelse return error.InvalidComponent;
    const bytes = try boundary.source.component_examples.emit(init.gpa, kind);
    defer init.gpa.free(bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
