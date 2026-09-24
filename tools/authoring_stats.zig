//! Read-only structural comparison of complete baseline and candidate BPI3 images.
const std = @import("std");
const data = @import("boundary_data");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    while (args.next()) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(16 << 20));
        defer init.gpa.free(bytes);
        var decoded = try data.program_image.decode(init.gpa, bytes);
        defer decoded.deinit();
        const p = decoded.program;
        var instructions: usize = 0;
        for (p.blocks) |block| instructions += block.instructions.len;
        try std.json.Stringify.value(.{
            .path = path,
            .bytes = bytes.len,
            .schemas = p.schemas.len,
            .functions = p.functions.len,
            .blocks = p.blocks.len,
            .instructions = instructions,
            .constructors = p.constructors.len,
            .captures = p.scopes.captures.len,
            .constants = p.constants.len,
        }, .{}, &output.interface);
        try output.interface.writeByte('\n');
    }
    try output.interface.flush();
}
