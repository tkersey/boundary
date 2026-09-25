//! Bounded timing of construction, lowering and emission in an already-built process.
const std = @import("std");
const b = @import("boundary");
const workload = @import("workload");
pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    for (0..21) |iteration| {
        var raw = b.computation.Builder.init(init.gpa);
        defer raw.deinit();
        const start = std.Io.Clock.awake.now(init.io);
        const module = try workload.Application.emit(&raw);
        const authored = std.Io.Clock.awake.now(init.io);
        var compiled = try b.program.compile(init.gpa, module);
        defer compiled.deinit();
        const lowered = std.Io.Clock.awake.now(init.io);
        const bytes = try init.gpa.alloc(u8, try b.data.program_image.encodedLength(compiled.program));
        defer init.gpa.free(bytes);
        _ = try compiled.encode(init.gpa, bytes);
        const encoded = std.Io.Clock.awake.now(init.io);
        if (iteration == 0) continue;
        try std.json.Stringify.value(.{
            .authorNs = start.durationTo(authored).nanoseconds,
            .lowerNs = authored.durationTo(lowered).nanoseconds,
            .encodeNs = lowered.durationTo(encoded).nanoseconds,
            .imageBytes = bytes.len,
        }, .{}, &output.interface);
        try output.interface.writeByte('\n');
    }
    try output.interface.flush();
}
