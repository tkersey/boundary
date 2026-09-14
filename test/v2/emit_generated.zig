// Copyright (c) 2026 Boundary contributors. MIT license.
//! Reusable seeded fixture emitter. This links no source or target evaluator.
const std = @import("std");
const boundary = @import("boundary");
const options = @import("source_options");
const generated = @import("generated_programs.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedSeed;
    const seed = try std.fmt.parseInt(u32, args[1], 10);
    var builder = boundary.source.Builder.init(init.gpa);
    defer builder.deinit();
    const module = try generated.build(&builder, seed);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (options.source) {
        try std.json.Stringify.value(module, .{ .emit_strings_as_arrays = true }, &output.interface);
        try output.interface.writeByte('\n');
    } else {
        var compiled = try boundary.program.compile(init.gpa, module);
        defer compiled.deinit();
        const bytes = try init.gpa.alloc(u8, try boundary.image_v2.encodedLength(compiled.program));
        defer init.gpa.free(bytes);
        _ = try compiled.encode(init.gpa, bytes);
        try output.interface.writeAll(bytes);
    }
    try output.interface.flush();
}
