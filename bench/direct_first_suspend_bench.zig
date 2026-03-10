const shift = @import("shift");
const std = @import("std");

const iterations: usize = 50_000;
const samples_per_run: usize = 5;
const warmup_iterations: usize = 20_000;

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

fn runSample() !struct { elapsed: u64, checksum: usize } {
    var runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer runtime.deinit();

    // Prime the runtime-owned stack/frame/suspension caches before timing the steady-state path.
    var warmup_i: usize = 0;
    while (warmup_i < warmup_iterations) : (warmup_i += 1) {
        bench_state.current = warmup_i;
        var warmup_outcome = try shift.reset(bench_spec, &runtime, bench_state.body);
        while (true) switch (warmup_outcome) {
            .complete => break,
            .cancelled => unreachable,
            .pending => |*pending| {
                warmup_outcome = try pending.resumeWith(bench_state.current);
            },
        };
    }

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
            .pending => |*pending| {
                outcome = try pending.resumeWith(bench_state.current);
            },
        };
    }

    return .{
        .elapsed = timer.read(),
        .checksum = sum,
    };
}

fn sortSamples(samples: *[samples_per_run]u64) void {
    var left_index: usize = 0;
    while (left_index < samples.len) : (left_index += 1) {
        var right_index: usize = left_index + 1;
        while (right_index < samples.len) : (right_index += 1) {
            if (samples[right_index] < samples[left_index]) {
                const tmp = samples[left_index];
                samples[left_index] = samples[right_index];
                samples[right_index] = tmp;
            }
        }
    }
}

/// Run the direct-style first-suspend benchmark.
pub fn main() anyerror!void {
    var samples = [_]u64{0} ** samples_per_run;
    var checksum: usize = 0;

    for (&samples, 0..) |*slot, sample_index| {
        const result = try runSample();
        slot.* = result.elapsed;
        if (sample_index == 0) {
            checksum = result.checksum;
        } else {
            std.debug.assert(checksum == result.checksum);
        }
    }

    var sorted = samples;
    sortSamples(&sorted);

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "samples={d} warmup_iterations={d} iterations={d} min_ns={d} median_ns={d} max_ns={d} checksum={d} sample_ns=[",
        .{
            samples_per_run,
            warmup_iterations,
            iterations,
            sorted[0],
            sorted[sorted.len / 2],
            sorted[sorted.len - 1],
            checksum,
        },
    );
    for (samples, 0..) |sample, sample_index| {
        if (sample_index != 0) try stdout.print(",", .{});
        try stdout.print("{d}", .{sample});
    }
    try stdout.print("]\n", .{});
    try stdout.flush();
}
