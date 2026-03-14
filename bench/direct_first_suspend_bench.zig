const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const BenchPrompt = shift.Prompt(.resume_then_transform, usize, usize, NoError);
const timed_iterations: usize = 50_000;
const warmup_iterations: usize = 20_000;
const samples_per_run: usize = 5;

const bench_state = struct {
    var prompt_ptr: ?*const BenchPrompt = null;
    var current: usize = 0;

    const handle_value = struct {
        /// Supply the resumed benchmark payload.
        pub fn resumeValue() usize {
            return current;
        }

        /// Preserve the resumed value for the benchmark body.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn body() shift.ResetError(NoError)!usize {
        const value = try shift.shift(usize, prompt_ptr.?, handle_value);
        return value + 1;
    }
};

const Sample = struct {
    checksum: usize,
    elapsed_ns: u64,
};

fn runSample(runtime: *shift.Runtime, prompt: *BenchPrompt, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var sum: usize = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        bench_state.current = i;
        sum += try shift.reset(runtime, prompt, bench_state.body);
    }

    return .{
        .checksum = sum,
        .elapsed_ns = timer.read(),
    };
}

fn sortAscending(values: []u64) void {
    var i: usize = 1;
    while (i < values.len) : (i += 1) {
        const current = values[i];
        var insert_idx = i;
        while (insert_idx > 0 and values[insert_idx - 1] > current) : (insert_idx -= 1) {
            values[insert_idx] = values[insert_idx - 1];
        }
        values[insert_idx] = current;
    }
}

/// Run the direct-style first-suspend benchmark.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer runtime.deinit();
    var prompt = BenchPrompt.init();
    bench_state.prompt_ptr = &prompt;

    _ = try runSample(&runtime, &prompt, warmup_iterations);

    var sample_ns = [_]u64{0} ** samples_per_run;
    var expected_checksum: ?usize = null;
    var i: usize = 0;
    while (i < samples_per_run) : (i += 1) {
        const sample = try runSample(&runtime, &prompt, timed_iterations);
        if (expected_checksum) |checksum| {
            if (checksum != sample.checksum) return error.ChecksumMismatch;
        } else {
            expected_checksum = sample.checksum;
        }
        sample_ns[i] = sample.elapsed_ns;
    }

    var sorted = sample_ns;
    sortAscending(&sorted);
    const min_ns = sorted[0];
    const median_ns = sorted[sorted.len / 2];
    const max_ns = sorted[sorted.len - 1];

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "timed_iterations={d} warmup_iterations={d} samples_per_run={d} checksum={d} sample_ns=[{d},{d},{d},{d},{d}] min_ns={d} median_ns={d} max_ns={d}\n",
        .{
            timed_iterations,
            warmup_iterations,
            samples_per_run,
            expected_checksum.?,
            sample_ns[0],
            sample_ns[1],
            sample_ns[2],
            sample_ns[3],
            sample_ns[4],
            min_ns,
            median_ns,
            max_ns,
        },
    );
    try stdout.flush();
}
