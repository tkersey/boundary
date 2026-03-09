const shift = @import("shift");
const std = @import("std");

const bench_spec = struct {
    /// Prompt tag.
    pub const tag = struct {};
    /// Outbound request type.
    pub const Request = usize;
    /// Resume value type.
    pub const Resume = usize;
    /// Final answer type.
    pub const Answer = usize;
    /// User error surface.
    pub const ErrorSet = error{};
};

const bench_state = struct {
    var current: usize = 0;

    fn body() shift.ResetError(bench_spec.ErrorSet)!bench_spec.Answer {
        const value = try shift.shift(bench_spec, current);
        return value + 1;
    }
};

/// Run the direct-style first-suspend benchmark.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer runtime.deinit();

    const iterations: usize = 50_000;
    var timer = try std.time.Timer.start();
    var sum: usize = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        bench_state.current = i;
        var outcome = try shift.reset(bench_spec, &runtime, bench_state.body);
        while (true) switch (outcome) {
            .complete => |answer| {
                sum += answer;
                break;
            },
            .cancelled => unreachable,
            .token => |*token| {
                outcome = try token.resumeWith(bench_state.current);
            },
        };
    }

    const elapsed = timer.read();
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("iterations={d} ns={d} checksum={d}\n", .{ iterations, elapsed, sum });
    try stdout.flush();
}
