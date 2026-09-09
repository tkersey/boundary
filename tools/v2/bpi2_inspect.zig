//! Read, admit and inspect BPI2 without linking any evaluator.
const std = @import("std");
const data = @import("boundary_data_v2");
pub fn main(init: std.process.Init) !void {
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().reader(init.io, &input_buffer);
    const bytes = try input.interface.allocRemaining(init.gpa, .limited(64 << 20));
    defer init.gpa.free(bytes);
    var decoded = try data.image.decode(init.gpa, bytes);
    defer decoded.deinit();
    const program = decoded.program;
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try std.json.Stringify.value(.{ .profile = program.roots.profile, .program_identity = std.fmt.bytesToHex(try data.image.identity(program), .lower), .schemas = program.schemas.len, .functions = program.functions.len, .blocks = program.blocks.len, .handlers = program.handlers.len, .regions = program.scopes.region_count }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
