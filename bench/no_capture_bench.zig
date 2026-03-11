const shift = @import("shift");
const std = @import("std");

const tag = struct {};
const NoError = error{};

const bench_state = struct {
    var current: usize = 0;

    fn body() shift.ResetError(NoError)!usize {
        return current;
    }
};

/// Run the no-capture benchmark for the direct-style reset fast path.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer runtime.deinit();

    const iterations: usize = 50_000;
    var timer = try std.time.Timer.start();
    var sum: usize = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        bench_state.current = i;
        sum += try shift.reset(tag, usize, NoError, &runtime, bench_state.body);
    }

    const elapsed = timer.read();
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("iterations={d} ns={d} checksum={d}\n", .{ iterations, elapsed, sum });
    try stdout.flush();
}
