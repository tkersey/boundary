// Copyright (c) 2026 Boundary contributors. MIT license.
//! Synthetic qualification emitter; each process independently authors its image.
const std = @import("std");
const data = @import("boundary_data");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode_name = args.next() orelse return error.MissingMode;
    const mode = std.meta.stringToEnum(data.coalescing.Mode, mode_name) orelse
        return error.InvalidMode;
    const count = try std.fmt.parseInt(usize, args.next() orelse return error.MissingCount, 10);
    if (args.next() != null or count == 0 or count > 256) return error.InvalidCount;
    var rounds: [16]data.coalescing.Round = undefined;
    var statistics: data.coalescing.Statistics = .{ .rounds = &rounds };
    var compiled = try @import("coalescing_tests.zig").closures(
        init.gpa,
        count,
        .{ .mode = mode, .statistics = &statistics },
    );
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
    var errors = std.Io.File.stderr().writer(init.io, &buffer);
    try std.json.Stringify.value(.{
        .count = count,
        .mode = mode,
        .bytes = bytes.len,
        .functions = compiled.program.functions.len,
        .constructors = compiled.program.constructors.len,
        .captures = compiled.program.scopes.captures.len,
        .outcome = statistics.outcome,
        .work = .{
            .limit = if (statistics.work.limit == std.math.maxInt(u64))
                @as(?u64, null)
            else
                statistics.work.limit,
            .units = statistics.work.units,
            .comparisons = statistics.work.comparisons,
            .rounds = statistics.work.rounds,
            .exhausted = statistics.work.exhausted,
        },
        .rounds = rounds[0..statistics.rounds_recorded],
    }, .{}, &errors.interface);
    try errors.interface.writeByte('\n');
    try errors.interface.flush();
}
