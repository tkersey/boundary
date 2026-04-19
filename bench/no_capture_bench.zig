const lowered_machine = @import("lowered_machine");
const std = @import("std");

const timed_iterations: usize = 50_000;
const warmup_iterations: usize = 20_000;
const samples_per_run: usize = 5;

const Sample = struct {
    checksum: usize,
    elapsed_ns: u64,
};

fn runSample(iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var sum: usize = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const steps = [_]lowered_machine.Step{
            .{ .set_final = .{ .i32 = @as(i32, @intCast(i)) } },
        };
        const state = lowered_machine.runSteps(&steps);
        sum += switch (state.final_result) {
            .i32 => |value| @as(usize, @intCast(value)),
            else => return error.UnexpectedFinalValue,
        };
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

/// Run the no-capture benchmark for the direct-style reset fast path.
pub fn main(init: std.process.Init) anyerror!void {
    _ = try runSample(warmup_iterations);

    var sample_ns = [_]u64{0} ** samples_per_run;
    var expected_checksum: ?usize = null;
    var i: usize = 0;
    while (i < samples_per_run) : (i += 1) {
        const sample = try runSample(timed_iterations);
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
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
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
