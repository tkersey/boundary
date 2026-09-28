//! Synthetic affine economics. Requested bytes exclude allocator metadata/RSS.
const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const Meter = @import("meter").Meter;
const fixture = @import("affine_capture.zig");

pub fn main(init: std.process.Init) !void {
    const a = init.gpa;
    const original = comptime fixture.recurrentFixture();
    const Row = struct { mode: []const u8, capture_words: usize, image_bytes: usize, construction_peak: usize, construction_allocated: usize, admission_peak: usize, prepared_bytes: usize, invocation_peak: usize, checkpoint_max: usize, transitions: usize };
    var rows: [3]Row = undefined;
    for (&rows, 0..) |*row, arm| {
        var construction: Meter = .{ .parent = a };
        var owned = if (arm == 0) try data.coalescing.run(construction.allocator(), original, .{}) else if (arm == 1) try data.affine_state.run(construction.allocator(), original, 0, null, 1000000, .{}) else try data.closed_compilation.run(construction.allocator(), original, .{ .contract = .semantic });
        defer owned.deinit();
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(owned.program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, owned.program, bytes);
        const storage = try a.alloc(u8, 64 << 20);
        defer a.free(storage);
        var workspace = world.Workspace.init(storage);
        var prepared = try world.Prepared.init(workspace.allocator(), bytes);
        const admission_peak = workspace.peak_payload;
        const prepared_bytes = try prepared.storageBytes();
        prepared.deinit();
        var args: [33]u8 = undefined;
        for ([_]u64{ 1, 2, 4, 8 }, 0..) |value, i| std.mem.writeInt(u64, args[i * 8 ..][0..8], value, .little);
        args[32] = 31;
        var execution: Meter = .{ .parent = a };
        var outcome = try world.invocation.invoke(execution.allocator(), .{ .image = bytes, .instance = .{ .initial_args = &args }, .quantum = 1 });
        defer outcome.deinit();
        var checkpoint_max: usize = 0;
        var transitions: usize = 1;
        while (outcome.record == .progressed) {
            const state = outcome.record.progressed orelse return error.MissingState;
            checkpoint_max = @max(checkpoint_max, state.len);
            var next = try world.invocation.invoke(execution.allocator(), .{ .image = bytes, .instance = .{ .state = state }, .quantum = 1 });
            outcome.deinit();
            outcome = next;
            next = undefined;
            transitions += 1;
            if (transitions > 10000) return error.NoCompletion;
        }
        if (outcome.record != .completed) return error.WrongOutcome;
        var p0: u64 = 1;
        var q0: u64 = 2;
        var r0: u64 = 4;
        for (0..31) |_| {
            const old = p0;
            p0 = q0;
            q0 = r0;
            r0 = old ^ 8 ^ 0xa5;
        }
        var expected: [8]u8 = undefined;
        std.mem.writeInt(u64, &expected, p0 ^ q0 ^ 8 ^ 0xa5, .little);
        if (!std.mem.eql(u8, &expected, outcome.record.completed)) return error.WrongResult;
        var capture_words: usize = 0;
        for (owned.program.constructors) |constructor| capture_words += owned.program.scopes.captures[@intCast(constructor.capture)].fields.len;
        row.* = .{ .mode = if (arm == 0) "p01-baseline" else if (arm == 1) "affine-only" else "semantic-pipeline", .capture_words = capture_words, .image_bytes = bytes.len, .construction_peak = construction.peak, .construction_allocated = construction.allocated, .admission_peak = admission_peak, .prepared_bytes = prepared_bytes, .invocation_peak = execution.peak, .checkpoint_max = checkpoint_max, .transitions = transitions };
    }
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .scope = "synthetic repeated affine cycle; one-step fresh invocation includes checkpoint output overlap; no timing claim", .rows = rows }, .{}, &out.interface);
    try out.interface.writeByte('\n');
    try out.interface.flush();
}
