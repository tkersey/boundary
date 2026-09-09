const boundary = @import("boundary");
const std = @import("std");
const options = @import("example_options");
const Application = struct {
    pub fn emit(builder: *boundary.computation.Builder) !boundary.computation.Module {
        const integer = try builder.scalar(u64);
        const unit = try builder.scalar(void);
        const entry = try builder.declare(&.{}, integer, &.{}, &.{});
        try builder.define(entry, try builder.pure(try builder.constant(u64, options.value)));
        return builder.module(entry, unit);
    }
};

pub fn main(init: std.process.Init) !void {
    var compiled = try boundary.program.lower(init.gpa, Application);
    defer compiled.deinit();
    const length = try boundary.image_v2.encodedLength(compiled.program);
    const buffer = try init.gpa.alloc(u8, length);
    defer init.gpa.free(buffer);
    const bytes = try compiled.encode(init.gpa, buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
