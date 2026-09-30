const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const fixtures = @import("rectangular.zig");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const rows = try std.fmt.parseInt(u64, args.next() orelse return error.Rows, 10);
    const columns = try std.fmt.parseInt(u64, args.next() orelse return error.Columns, 10);
    if (args.next() != null) return error.Arguments;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const original = try fixtures.rectangle(arena.allocator(), rows, columns);
    const storage = try init.gpa.alloc(u8, 64 << 20);
    defer init.gpa.free(storage);
    var samples: [9]f64 = undefined;
    var peak: usize = 0;
    var image_bytes: usize = 0;
    var stats: data.closed_compilation.Statistics = .{};
    for (0..12) |window| {
        var workspace = world.Workspace.init(storage);
        const start = std.Io.Clock.awake.now(init.io);
        var result = try data.closed_compilation.run(workspace.allocator(), original, .{ .contract = .semantic, .statistics = &stats });
        image_bytes = try data.program_image.encodedLength(result.program);
        result.deinit();
        const elapsed = start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds;
        if (workspace.live_payload != 0) return error.RetainedCompilerMemory;
        peak = @max(peak, workspace.peak_payload);
        if (window >= 3) samples[window - 3] = @floatFromInt(elapsed);
    }
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .samplesNs = samples, .peakBytes = peak, .imageBytes = image_bytes, .statistics = stats }, .{}, &out.interface);
    try out.interface.writeByte('\n');
    try out.interface.flush();
}
