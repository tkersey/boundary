const std = @import("std");
const world = @import("world");
const data = @import("boundary_data");
const protocol = data.invocation;
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const phase = args.next() orelse return error.Phase;
    const path = args.next() orelse return error.Path;
    const admission = std.mem.eql(u8, phase, "admission");
    const cycle = std.mem.eql(u8, phase, "cycle");
    if (!admission and !cycle and !std.mem.eql(u8, phase, "fresh")) return error.Phase;
    var expected: [32]u8 = undefined;
    if (!admission) {
        const hex = args.next() orelse return error.Digest;
        if (hex.len != 64) return error.Digest;
        _ = try std.fmt.hexToBytes(&expected, hex);
    }
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(64 << 20));
    defer init.gpa.free(bytes);
    const storage = try init.gpa.alloc(u8, 256 << 20);
    defer init.gpa.free(storage);
    const output = try init.gpa.alloc(u8, 8 << 20);
    defer init.gpa.free(output);
    const input_buffer = try init.gpa.alloc(u8, 8 << 20);
    defer init.gpa.free(input_buffer);
    var input: ?protocol.Owned(protocol.Input) = if (!admission) try protocol.decode(protocol.Input, init.gpa, bytes) else null;
    defer if (input) |*value| value.deinit();
    var samples: [9]f64 = undefined;
    var peak: usize = 0;
    var retained: usize = 0;
    for (0..12) |window| {
        var elapsed: u64 = 0;
        const batch: usize = if (admission) 64 else if (cycle) 1 else 16;
        for (0..batch) |_| {
            var arena = world.Workspace.init(storage);
            const start = std.Io.Clock.awake.now(init.io);
            if (admission) {
                var prepared = try world.Prepared.init(arena.allocator(), bytes);
                elapsed += @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
                peak = @max(peak, arena.peak_payload);
                retained = @max(retained, arena.live_payload);
                prepared.deinit();
            } else {
                var invocation = input.?.value;
                invocation.quantum = if (cycle) 1 else null;
                var encoded = try protocol.encode(protocol.Input, init.gpa, invocation, input_buffer);
                var steps: usize = 0;
                while (true) {
                    if (steps == 4096) return error.StepLimit;
                    steps += 1;
                    arena = world.Workspace.init(storage);
                    const result = try world.invocation.invokeInto(arena.allocator(), encoded, output);
                    peak = @max(peak, arena.peak_payload);
                    var decoded = try protocol.decode(protocol.Outcome, init.gpa, result);
                    defer decoded.deinit();
                    if (decoded.value == .requested) {
                        var request = try protocol.decode(protocol.Request, init.gpa, decoded.value.requested.request);
                        defer request.deinit();
                        if (!std.mem.eql(u8, request.value.binding.semantic_identity, "p29/opaque") or request.value.binding.payload.len != 8) return error.UnexpectedEffect;
                        var value: [8]u8 = undefined;
                        std.mem.writeInt(u64, &value, std.mem.readInt(u64, request.value.binding.payload[0..8], .little) ^ 0x55, .little);
                        const reply = try protocol.encodeOwned(protocol.Result, init.gpa, .{ .request_identity = request.value.request_identity, .value = &value });
                        defer init.gpa.free(reply);
                        invocation.instance = .{ .state = decoded.value.requested.state orelse return error.MissingState };
                        invocation.control = .{ .reply = reply };
                        encoded = try protocol.encode(protocol.Input, init.gpa, invocation, input_buffer);
                        continue;
                    }
                    if (decoded.value != .progressed and decoded.value != .yielded) {
                        elapsed += @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
                        if (!std.mem.eql(u8, &data.wire.digest(result), &expected)) return error.OutcomeMismatch;
                        break;
                    }
                    if (!cycle and decoded.value == .progressed) return error.UnexpectedInterruption;
                    const yielded = decoded.value == .yielded;
                    invocation.instance = .{ .state = if (yielded) decoded.value.yielded.? else decoded.value.progressed.? };
                    invocation.control = if (yielded) .resume_yield else .none;
                    encoded = try protocol.encode(protocol.Input, init.gpa, invocation, input_buffer);
                }
            }
            if (arena.live_payload != 0) return error.LeakedRuntimePayload;
        }
        if (window >= 3) samples[window - 3] = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(batch));
    }
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .samplesNs = samples, .peakBytes = peak, .retainedBytes = retained }, .{}, &out.interface);
    try out.interface.writeByte('\n');
    try out.interface.flush();
}
