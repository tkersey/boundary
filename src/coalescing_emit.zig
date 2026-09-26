// Copyright (c) 2026 Boundary contributors. MIT license.
//! Synthetic qualification emitter; each process independently authors its image.
const std = @import("std");
const data = @import("boundary_data");
const components = @import("coalescing_component_cases.zig");
const trees = @import("coalescing_tree_cases.zig");
const edges = @import("coalescing_edge_cases.zig");
const recursive = @import("coalescing_recursive_cases.zig");

fn emitComponent(init: std.process.Init, kind: components.Kind, mode: data.coalescing.Mode) !void {
    const object = try components.emit(init.gpa, kind, mode);
    defer init.gpa.free(object);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(object);
    try output.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode_name = args.next() orelse return error.MissingMode;
    const mode = std.meta.stringToEnum(data.coalescing.Mode, mode_name) orelse
        return error.InvalidMode;
    const selection = args.next() orelse return error.MissingCount;
    if (std.meta.stringToEnum(components.Kind, selection)) |kind| {
        if (args.next() != null) return error.UnexpectedArgument;
        return emitComponent(init, kind, mode);
    }
    const tree = std.meta.stringToEnum(trees.Kind, selection);
    const edge = std.meta.stringToEnum(edges.Kind, selection);
    const recursion = std.meta.stringToEnum(recursive.Kind, selection);
    const seed = if (std.mem.startsWith(u8, selection, "generated-"))
        try std.fmt.parseInt(usize, selection[10..], 10)
    else
        @as(?usize, null);
    const count = if (tree != null) 8 else if (edge != null or seed != null or recursion != null) 3 else try std.fmt.parseInt(usize, selection, 10);
    if (args.next() != null or count == 0 or count > 256) return error.InvalidCount;
    var rounds: [16]data.coalescing.Round = undefined;
    var statistics: data.coalescing.Statistics = .{ .rounds = &rounds };
    const options: data.coalescing.Options = .{ .mode = mode, .statistics = &statistics };
    var compiled = if (recursion) |kind|
        try recursive.compile(init.gpa, kind, options)
    else if (seed) |value|
        try edges.generated(init.gpa, value, options)
    else if (edge) |kind|
        try edges.compile(init.gpa, kind, options)
    else if (tree) |kind|
        try trees.compile(init.gpa, kind, options)
    else
        try @import("coalescing_tests.zig").closures(
            init.gpa,
            count,
            options,
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
