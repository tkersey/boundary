const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const BenchPrompt = shift.Prompt(usize, NoError);

const bench_state = struct {
    var prompt_ptr: ?*const BenchPrompt = null;
    var current: usize = 0;

    fn handleValue(k: *shift.Continuation(usize, BenchPrompt)) shift.ResetError(NoError)!usize {
        return try k.resumeWith(current);
    }

    fn body() shift.ResetError(NoError)!usize {
        const value = try shift.shift(usize, prompt_ptr.?, handleValue);
        return value + 1;
    }
};

/// Run the direct-style first-suspend benchmark.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer runtime.deinit();
    var prompt = BenchPrompt.init();
    bench_state.prompt_ptr = &prompt;

    const iterations: usize = 50_000;
    var timer = try std.time.Timer.start();
    var sum: usize = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        bench_state.current = i;
        sum += try shift.reset(&runtime, &prompt, bench_state.body);
    }

    const elapsed = timer.read();
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("iterations={d} ns={d} checksum={d}\n", .{ iterations, elapsed, sum });
    try stdout.flush();
}
