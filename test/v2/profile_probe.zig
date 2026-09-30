// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const original = @import("call_patterns.zig").repeated;
const Profile = data.optimization_profile;
const Observation = struct { profile: ?Profile.Owned, steps: usize };

fn execute(allocator: std.mem.Allocator, bytes: []const u8, collect: bool) !Observation {
    var collector: ?Profile.Collector = if (collect) try Profile.Collector.init(allocator, original) else null;
    defer if (collector) |*value| value.deinit();
    var input = [_]u8{0} ** 18;
    input[0] = 5;
    input[8] = 3;
    var session = try world.Session.initImage(allocator, bytes, &input);
    defer session.deinit();
    var steps: usize = 0;
    while (steps < 1000) {
        if (collector) |*value| if (session.roots.current) |current| {
            const node = try session.store.get(current);
            if (node == .control and (try session.frames.get(current.id)).position == 0)
                try value.observe(@intCast(node.control.block));
        };
        steps += 1;
        switch (try session.run(1)) {
            .progressed => {},
            .completed => |value| {
                const result = try session.bytes(&value);
                if (std.mem.readInt(u64, result[0..8], .little) != ((~@as(u64, 5)) | (~@as(u64, 3)))) return error.ResultMismatch;
                return .{ .profile = if (collector) |value_| try value_.snapshot(allocator) else null, .steps = steps };
            },
            else => return error.OutcomeMismatch,
        }
    }
    return error.StepLimit;
}
fn save(init: std.process.Init, directory: []const u8, name: []const u8, program: data.activation.Program) !void {
    const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(program));
    defer init.gpa.free(bytes);
    _ = try data.program_image.encode(init.gpa, program, bytes);
    const path = try std.fmt.allocPrint(init.gpa, "{s}/{s}.bpi3", .{ directory, name });
    defer init.gpa.free(path);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = bytes });
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.Mode;
    const argument = args.next() orelse return error.Argument;
    if (args.next() != null) return error.Arguments;
    const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(original));
    defer init.gpa.free(bytes);
    _ = try data.program_image.encode(init.gpa, original, bytes);
    if (std.mem.eql(u8, mode, "collect")) {
        const collect = std.mem.eql(u8, argument, "enabled");
        if (!collect and !std.mem.eql(u8, argument, "disabled")) return error.Argument;
        var samples: [9]f64 = undefined;
        var observed_steps: usize = 0;
        const storage = try init.gpa.alloc(u8, 64 << 20);
        defer init.gpa.free(storage);
        var peak: usize = 0;
        var retained_profile: usize = 0;
        for (0..12) |window| {
            var elapsed: u64 = 0;
            for (0..64) |_| {
                var workspace = world.Workspace.init(storage);
                const start = std.Io.Clock.awake.now(init.io);
                var observation = try execute(workspace.allocator(), bytes, collect);
                observed_steps = observation.steps;
                retained_profile = @max(retained_profile, workspace.live_payload);
                if (observation.profile) |*profile| profile.deinit();
                elapsed += @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
                peak = @max(peak, workspace.peak_payload);
                if (workspace.live_payload != 0) return error.RetainedWorkingMemory;
            }
            if (window >= 3) samples[window - 3] = @as(f64, @floatFromInt(elapsed)) / 64;
        }
        var buffer: [4096]u8 = undefined;
        var out = std.Io.File.stdout().writer(init.io, &buffer);
        try std.json.Stringify.value(.{ .samplesNs = samples, .logicalSteps = observed_steps, .collection = collect, .peakBytes = peak, .retainedProfileBytes = retained_profile }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
        return;
    }
    if (!std.mem.eql(u8, mode, "emit")) return error.Mode;
    var observed = try execute(init.gpa, bytes, true);
    defer observed.profile.?.deinit();
    const record = observed.profile.?.record;
    const encoded = try init.gpa.alloc(u8, try Profile.encodedLength(record));
    defer init.gpa.free(encoded);
    const path = try std.fmt.allocPrint(init.gpa, "{s}/training.bpf1", .{argument});
    defer init.gpa.free(path);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = try Profile.encode(record, encoded) });
    var structural = try data.coalescing.run(init.gpa, original, .{});
    defer structural.deinit();
    try save(init, argument, "structural", structural.program);
    var limited = try data.call_patterns.run(init.gpa, original, null, .{ .max_variants = 1 });
    defer limited.deinit();
    try save(init, argument, "limited", limited.program);
    var profiled = try data.call_patterns.run(init.gpa, original, null, .{ .max_variants = 1, .profile = record });
    defer profiled.deinit();
    try save(init, argument, "profiled", profiled.program);
    var ordinary = try data.closed_compilation.run(init.gpa, original, .{ .contract = .semantic });
    defer ordinary.deinit();
    try save(init, argument, "ordinary", ordinary.program);
    var shared = try data.closed_compilation.run(init.gpa, original, .{ .contract = .semantic, .profile = .{ .record = record, .max_variants = 1 } });
    defer shared.deinit();
    try save(init, argument, "shared", shared.program);
}
