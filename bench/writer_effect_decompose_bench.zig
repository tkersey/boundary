const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const timed_iterations: usize = 50_000;
const warmup_iterations: usize = 20_000;
const samples_per_run: usize = 5;

const WriterInstance = shift.effect.writer.Instance(usize, NoError);

const Sample = struct {
    checksum: usize,
    elapsed_ns: u64,
};

const BenchWriterState = struct {
    allocator: std.mem.Allocator,
    first_item: ?usize = null,
    items: std.ArrayList(usize) = .empty,

    fn init(allocator: std.mem.Allocator) BenchWriterState {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *BenchWriterState) void {
        self.items.deinit(self.allocator);
    }

    fn append(self: *BenchWriterState, item: usize) !void {
        if (self.first_item == null and self.items.items.len == 0) {
            self.first_item = item;
            return;
        }
        if (self.items.items.len == 0) {
            try self.items.ensureTotalCapacity(self.allocator, 2);
            self.items.appendAssumeCapacity(self.first_item.?);
            self.first_item = null;
        }
        try self.items.append(self.allocator, item);
    }

    fn materialize(self: *BenchWriterState, allocator: std.mem.Allocator) ![]usize {
        if (self.items.items.len != 0) {
            return try self.items.toOwnedSlice(allocator);
        }
        if (self.first_item) |item| {
            const slice = try allocator.alloc(usize, 1);
            slice[0] = item;
            self.first_item = null;
            return slice;
        }
        return try allocator.alloc(usize, 0);
    }
};

fn preserveValue(value: anytype) @TypeOf(value) {
    const preserved = value;
    std.mem.doNotOptimizeAway(preserved);
    return preserved;
}

const LaneReport = struct {
    items_per_body: usize,
    raw_samples: [samples_per_run]u64,
    effect_samples: [samples_per_run]u64,
    finalize_samples: [samples_per_run]u64,
    raw_checksum: usize,
    effect_checksum: usize,
    finalize_checksum: usize,
};

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
    return .{ .min = sorted[0], .median = sorted[sorted.len / 2], .max = sorted[sorted.len - 1] };
}

const raw_writer = struct {
    fn body(allocator: std.mem.Allocator, comptime items_per_body: usize) !usize {
        var items: std.ArrayList(usize) = .empty;
        defer items.deinit(allocator);
        var current: usize = 0;
        while (current < items_per_body) : (current += 1) {
            try items.append(allocator, current + 1);
        }
        const owned = try items.toOwnedSlice(allocator);
        defer allocator.free(owned);
        std.mem.doNotOptimizeAway(owned.ptr);
        var checksum: usize = owned.len;
        for (owned) |item| checksum += item;
        return checksum;
    }
};

const effect_writer = struct {
    fn body(comptime Cap: type, ctx: anytype, comptime items_per_body: usize) shift.ResetError(NoError)!usize {
        var current: usize = 0;
        while (current < items_per_body) : (current += 1) {
            try shift.effect.writer.tell(Cap, ctx, current + 1);
        }
        return 0;
    }
};

fn runWriterRawSample(allocator: std.mem.Allocator, comptime items_per_body: usize, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        checksum += preserveValue(try raw_writer.body(allocator, items_per_body));
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runWriterEffectSample(runtime: *shift.Runtime, instance: *const WriterInstance, allocator: std.mem.Allocator, comptime items_per_body: usize, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        const body = struct {
            /// Re-enter the current writer handle with a fixed item count.
            pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!usize {
                return try effect_writer.body(Cap, ctx, items_per_body);
            }
        };
        const result = preserveValue(try shift.effect.writer.handle(usize, usize, runtime, instance, allocator, body));
        defer allocator.free(result.items);
        std.mem.doNotOptimizeAway(result.items.ptr);
        var item_checksum: usize = result.items.len + result.value;
        for (result.items) |item| item_checksum += item;
        checksum += item_checksum;
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runWriterFinalizeOnlySample(allocator: std.mem.Allocator, comptime items_per_body: usize, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        var state = BenchWriterState.init(allocator);
        defer state.deinit();
        var current: usize = 0;
        while (current < items_per_body) : (current += 1) {
            try state.append(current + 1);
        }
        const owned = preserveValue(try state.materialize(allocator));
        defer allocator.free(owned);
        std.mem.doNotOptimizeAway(owned.ptr);
        var lane_checksum: usize = owned.len;
        for (owned) |item| lane_checksum += item;
        checksum += lane_checksum;
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn printLine(writer: anytype, report: *const LaneReport) !void {
    const raw_stats = summarizeSamples(&report.raw_samples);
    const effect_stats = summarizeSamples(&report.effect_samples);
    const finalize_stats = summarizeSamples(&report.finalize_samples);
    try writer.print(
        "items={d} raw_checksum={d} effect_checksum={d} finalize_checksum={d} raw_median_ns={d} effect_median_ns={d} finalize_median_ns={d} effect_over_raw={d:.4} finalize_share={d:.4}\n",
        .{
            report.items_per_body,
            report.raw_checksum,
            report.effect_checksum,
            report.finalize_checksum,
            raw_stats.median,
            effect_stats.median,
            finalize_stats.median,
            @as(f64, @floatFromInt(effect_stats.median)) / @as(f64, @floatFromInt(raw_stats.median)),
            @as(f64, @floatFromInt(finalize_stats.median)) / @as(f64, @floatFromInt(effect_stats.median)),
        },
    );
}

fn runLane(runtime: *shift.Runtime, instance: *const WriterInstance, allocator: std.mem.Allocator, comptime items_per_body: usize) !LaneReport {
    _ = try runWriterRawSample(allocator, items_per_body, warmup_iterations);
    _ = try runWriterEffectSample(runtime, instance, allocator, items_per_body, warmup_iterations);
    _ = try runWriterFinalizeOnlySample(allocator, items_per_body, warmup_iterations);

    var raw_samples = [_]u64{0} ** samples_per_run;
    var effect_samples = [_]u64{0} ** samples_per_run;
    var finalize_samples = [_]u64{0} ** samples_per_run;
    var raw_checksum: ?usize = null;
    var effect_checksum: ?usize = null;
    var finalize_checksum: ?usize = null;

    var index: usize = 0;
    while (index < samples_per_run) : (index += 1) {
        const raw_sample = try runWriterRawSample(allocator, items_per_body, timed_iterations);
        const effect_sample = try runWriterEffectSample(runtime, instance, allocator, items_per_body, timed_iterations);
        const finalize_sample = try runWriterFinalizeOnlySample(allocator, items_per_body, timed_iterations);

        if (raw_checksum) |checksum| {
            if (checksum != raw_sample.checksum) return error.RawChecksumMismatch;
        } else raw_checksum = raw_sample.checksum;
        if (effect_checksum) |checksum| {
            if (checksum != effect_sample.checksum) return error.EffectChecksumMismatch;
        } else effect_checksum = effect_sample.checksum;
        if (finalize_checksum) |checksum| {
            if (checksum != finalize_sample.checksum) return error.FinalizeChecksumMismatch;
        } else finalize_checksum = finalize_sample.checksum;

        raw_samples[index] = raw_sample.elapsed_ns;
        effect_samples[index] = effect_sample.elapsed_ns;
        finalize_samples[index] = finalize_sample.elapsed_ns;
    }

    return .{
        .items_per_body = items_per_body,
        .raw_samples = raw_samples,
        .effect_samples = effect_samples,
        .finalize_samples = finalize_samples,
        .raw_checksum = raw_checksum.?,
        .effect_checksum = effect_checksum.?,
        .finalize_checksum = finalize_checksum.?,
    };
}

/// Decompose writer-effect append and finalization costs for representative item counts.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer runtime.deinit();
    var instance = WriterInstance.init();

    const lane1 = try runLane(&runtime, &instance, std.heap.smp_allocator, 1);
    const lane16 = try runLane(&runtime, &instance, std.heap.smp_allocator, 16);
    const lane64 = try runLane(&runtime, &instance, std.heap.smp_allocator, 64);

    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "timed_iterations={d} warmup_iterations={d} samples_per_run={d}\n",
        .{ timed_iterations, warmup_iterations, samples_per_run },
    );
    try printLine(stdout, &lane1);
    try printLine(stdout, &lane16);
    try printLine(stdout, &lane64);
    try stdout.flush();
}
