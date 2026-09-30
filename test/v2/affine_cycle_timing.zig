//! Frozen-input timing for a complete quantum-one checkpoint/restore cycle.
const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const path = args.next() orelse return error.Input;
    const hex = args.next() orelse return error.Digest;
    if (args.next() != null or hex.len != 64) return error.Arguments;
    var expected: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, hex);
    const a = init.gpa;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20));
    defer a.free(bytes);
    var decoded = try data.invocation.decode(data.invocation.Input, a, bytes);
    defer decoded.deinit();
    const input = decoded.value;
    if (input.instance != .initial_args or input.control != .none) return error.InitialInputRequired;
    var samples: [9]i96 = undefined;
    var transitions: usize = 0;
    for (0..12) |iteration| {
        const begin = std.Io.Clock.awake.now(init.io);
        var current = try world.invocation.invoke(a, .{ .image = input.image, .instance = input.instance, .quantum = 1 });
        defer current.deinit();
        var steps: usize = 1;
        while (current.record == .progressed) {
            const state = current.record.progressed orelse return error.MissingState;
            var next = try world.invocation.invoke(a, .{ .image = input.image, .instance = .{ .state = state }, .quantum = 1 });
            current.deinit();
            current = next;
            next = undefined;
            steps += 1;
            if (steps > 10000) return error.NoCompletion;
        }
        const end = std.Io.Clock.awake.now(init.io);
        if (current.record != .completed) return error.UnexpectedOutcome;
        const output = try data.invocation.encodeOwned(data.invocation.Outcome, a, current.record);
        defer a.free(output);
        if (!std.mem.eql(u8, &expected, &data.wire.digest(output))) return error.OutcomeMismatch;
        if (iteration != 0 and transitions != steps) return error.UnstableTransitions;
        transitions = steps;
        if (iteration >= 3) samples[iteration - 3] = begin.durationTo(end).nanoseconds;
    }
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .samplesNs = samples, .transitions = transitions, .scope = "Complete quantum-one fresh invocation/checkpoint/restore cycle; not isolated phase latency" }, .{}, &out.interface);
    try out.interface.writeByte('\n');
    try out.interface.flush();
}
