//! Convert an admitted BPI2/BPC1 image to the deterministic compact-selected form.
const std = @import("std");
const data = @import("boundary_data_v2");

pub fn main(init: std.process.Init) !void {
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().reader(init.io, &input_buffer);
    const bytes = try input.interface.allocRemaining(init.gpa, .unlimited);
    defer init.gpa.free(bytes);
    var decoded = try data.compact_image.decode(init.gpa, bytes);
    defer decoded.deinit();
    const length = try data.compact_image.encodedLength(init.gpa, decoded.program);
    const output_bytes = try init.gpa.alloc(u8, length);
    defer init.gpa.free(output_bytes);
    const encoded = try data.compact_image.encode(init.gpa, decoded.program, output_bytes);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try output.interface.writeAll(encoded);
    try output.interface.flush();
}
