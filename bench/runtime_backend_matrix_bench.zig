const bridge_manifest = @import("direct_style_bridge_manifest");
const lowered_runtime = @import("private_lowered_runtime");
const stack_runtime = @import("runtime_stack_baseline");
const std = @import("std");

const timed_iterations: usize = 10_000;
const warmup_iterations: usize = 2_000;
const samples_per_run: usize = 5;

const Sample = struct {
    checksum: u64,
    elapsed_ns: u64,
};

fn preserveValue(value: anytype) @TypeOf(value) {
    const preserved = value;
    std.mem.doNotOptimizeAway(preserved);
    return preserved;
}

fn checksum(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

fn laneClass(case_id: []const u8, source_kind: bridge_manifest.SourceKind) []const u8 {
    if (std.mem.eql(u8, case_id, "nested_workflow")) return "workflow";
    if (source_kind == .witness) return "witness";
    if (std.mem.endsWith(u8, case_id, "_basic")) return "effect";
    return "example";
}

fn targetRatioMax(case_id: []const u8, source_kind: bridge_manifest.SourceKind) f64 {
    if (std.mem.eql(u8, case_id, "nested_workflow")) return 1.50;
    if (std.mem.eql(u8, case_id, "state_basic")) return 1.95;
    if (std.mem.eql(u8, case_id, "reader_basic")) return 2.50;
    if (source_kind == .witness) return 1.25;
    if (std.mem.endsWith(u8, case_id, "_basic")) return 1.35;
    return 1.35;
}

fn sortAscending(values: []u64) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const current = values[index];
        var insert_idx = index;
        while (insert_idx > 0 and values[insert_idx - 1] > current) : (insert_idx -= 1) {
            values[insert_idx] = values[insert_idx - 1];
        }
        values[insert_idx] = current;
    }
}

fn summarizeSamples(values: *const [samples_per_run]u64) struct { min: u64, median: u64, max: u64 } {
    var sorted = values.*;
    sortAscending(&sorted);
    return .{
        .min = sorted[0],
        .median = sorted[sorted.len / 2],
        .max = sorted[sorted.len - 1],
    };
}

fn runStackSample(case_id: []const u8, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var rolling_checksum: u64 = 0;

    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        var buffer: [4096]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        try stack_runtime.runCaseId(&writer, case_id);
        const transcript = writer.buffered();
        rolling_checksum +%= preserveValue(checksum(transcript));
    }

    return .{
        .checksum = rolling_checksum,
        .elapsed_ns = timer.read(),
    };
}

fn runLoweredSample(case_id: []const u8, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var rolling_checksum: u64 = 0;

    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        var buffer: [4096]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        _ = try lowered_runtime.runCaseId(&writer, case_id);
        const transcript = writer.buffered();
        rolling_checksum +%= preserveValue(checksum(transcript));
    }

    return .{
        .checksum = rolling_checksum,
        .elapsed_ns = timer.read(),
    };
}

fn printArray(values: [samples_per_run]u64) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const out = &stdout_writer.interface;
    try out.writeAll("[");
    for (values, 0..) |value, idx| {
        if (idx != 0) try out.writeAll(",");
        try out.print("{d}", .{value});
    }
    try out.writeAll("]");
    try out.flush();
}

/// Compare the current stack runtime against the private lowered runtime seam.
pub fn main() anyerror!void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const out = &stdout_writer.interface;

    var lane_count: usize = 0;
    for (bridge_manifest.cases) |case| {
        if (case.status == .supported) lane_count += 1;
    }

    try out.print(
        "schema_version=1 lanes={d} timed_iterations={d} warmup_iterations={d} samples_per_run={d}\n",
        .{ lane_count, timed_iterations, warmup_iterations, samples_per_run },
    );

    for (bridge_manifest.cases) |case| {
        if (case.status != .supported) continue;

        _ = try runStackSample(case.case_id, warmup_iterations);
        _ = try runLoweredSample(case.case_id, warmup_iterations);

        var stack_samples = [_]u64{0} ** samples_per_run;
        var lowered_samples = [_]u64{0} ** samples_per_run;
        var stack_checksum: ?u64 = null;
        var lowered_checksum: ?u64 = null;

        var index: usize = 0;
        while (index < samples_per_run) : (index += 1) {
            const stack_sample = try runStackSample(case.case_id, timed_iterations);
            const lowered_sample = try runLoweredSample(case.case_id, timed_iterations);

            if (stack_checksum) |value| {
                if (value != stack_sample.checksum) return error.StackChecksumMismatch;
            } else {
                stack_checksum = stack_sample.checksum;
            }

            if (lowered_checksum) |value| {
                if (value != lowered_sample.checksum) return error.LoweredChecksumMismatch;
            } else {
                lowered_checksum = lowered_sample.checksum;
            }

            if (stack_sample.checksum != lowered_sample.checksum) return error.RuntimeBackendParityMismatch;

            stack_samples[index] = stack_sample.elapsed_ns;
            lowered_samples[index] = lowered_sample.elapsed_ns;
        }

        const stack_summary = summarizeSamples(&stack_samples);
        const lowered_summary = summarizeSamples(&lowered_samples);
        const observed_ratio = @as(f64, @floatFromInt(lowered_summary.median)) / @as(f64, @floatFromInt(stack_summary.median));

        try out.print(
            "lane={s} lane_class={s} target_ratio_max={d:.2} stack_checksum={d} lowered_checksum={d} stack_sample_ns=",
            .{
                case.case_id,
                laneClass(case.case_id, case.source_kind),
                targetRatioMax(case.case_id, case.source_kind),
                stack_checksum.?,
                lowered_checksum.?,
            },
        );
        try out.flush();
        try printArray(stack_samples);
        try out.print(
            " lowered_sample_ns=",
            .{},
        );
        try out.flush();
        try printArray(lowered_samples);
        try out.print(
            " stack_min_ns={d} stack_median_ns={d} stack_max_ns={d} lowered_min_ns={d} lowered_median_ns={d} lowered_max_ns={d} observed_ratio={d:.16}\n",
            .{
                stack_summary.min,
                stack_summary.median,
                stack_summary.max,
                lowered_summary.min,
                lowered_summary.median,
                lowered_summary.max,
                observed_ratio,
            },
        );
    }

    try out.flush();
}
