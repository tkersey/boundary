const ability = @import("ability");
const std = @import("std");

const NoError = error{};
const timed_iterations: usize = 50_000;
const warmup_iterations: usize = 20_000;
const samples_per_run: usize = 5;
const preserveValue = ability.preserveValue;

const ResourceInstance = ability.effect.resource.Instance(usize, NoError);

const Sample = struct {
    checksum: usize,
    elapsed_ns: u64,
};

fn elapsedNsSince(io: std.Io, start: std.Io.Timestamp) u64 {
    return @intCast(start.durationTo(std.Io.Timestamp.now(io, .boot)).toNanoseconds());
}

const resource_inline_capacity = 4;

const LaneReport = struct {
    items_per_body: usize,
    raw_samples: [samples_per_run]u64,
    effect_samples: [samples_per_run]u64,
    cleanup_samples: [samples_per_run]u64,
    raw_checksum: usize,
    effect_checksum: usize,
    cleanup_checksum: usize,
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

const raw_resource = struct {
    var current_base: usize = 0;
    var acquire_count: usize = 0;
    var release_sink: usize = 0;

    fn acquire() usize {
        const value = current_base + acquire_count + 1;
        acquire_count += 1;
        return value;
    }

    fn release(resource: usize) void {
        release_sink +%= resource;
    }

    fn body(allocator: std.mem.Allocator, comptime items_per_body: usize) !usize {
        acquire_count = 0;
        release_sink = 0;
        var resources: std.ArrayList(usize) = .empty;
        defer resources.deinit(allocator);
        var checksum: usize = 0;
        var items_remaining = items_per_body;
        while (items_remaining != 0) : (items_remaining -= 1) {
            const resource = acquire();
            try resources.append(allocator, resource);
            checksum += resource;
        }
        while (resources.items.len != 0) {
            const resource = resources.items[resources.items.len - 1];
            resources.items.len -= 1;
            release(resource);
        }
        return checksum;
    }
};

const effect_resource = struct {
    const manager = struct {
        /// Acquire the next synthetic resource value.
        pub fn acquire() usize {
            return raw_resource.acquire();
        }

        /// Release one synthetic resource value.
        pub fn release(resource: usize) void {
            raw_resource.release(resource);
        }
    };

    fn body(comptime Cap: type, ctx: anytype, comptime items_per_body: usize) ability.ResetError(NoError)!usize {
        var checksum: usize = 0;
        var items_remaining = items_per_body;
        while (items_remaining != 0) : (items_remaining -= 1) {
            checksum += try ability.effect.resource.acquire(Cap, ctx);
        }
        return checksum;
    }
};

const BenchCleanupFrame = struct {
    allocator: std.mem.Allocator,
    inline_resources: [resource_inline_capacity]?usize = [_]?usize{null} ** resource_inline_capacity,
    inline_len: usize = 0,
    resources: std.ArrayList(usize) = .empty,

    fn init(allocator: std.mem.Allocator) BenchCleanupFrame {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *BenchCleanupFrame) void {
        self.resources.deinit(self.allocator);
    }

    fn fill(self: *BenchCleanupFrame, base: usize, comptime items_per_body: usize) !usize {
        var checksum: usize = 0;
        var current: usize = 0;
        while (current < items_per_body) : (current += 1) {
            const resource = base + current + 1;
            try self.appendResource(resource);
            checksum += resource;
        }
        return checksum;
    }

    fn appendResource(self: *BenchCleanupFrame, resource: usize) !void {
        if (self.resources.items.len == 0 and self.inline_len < resource_inline_capacity) {
            self.inline_resources[self.inline_len] = resource;
            self.inline_len += 1;
            return;
        }
        if (self.resources.items.len == 0) {
            try self.resources.ensureTotalCapacity(self.allocator, resource_inline_capacity * 2);
            for (self.inline_resources[0..self.inline_len]) |existing| {
                self.resources.appendAssumeCapacity(existing.?);
            }
            self.inline_len = 0;
        }
        try self.resources.append(self.allocator, resource);
    }

    fn popResource(self: *BenchCleanupFrame) ?usize {
        if (self.resources.items.len != 0) {
            const resource = self.resources.items[self.resources.items.len - 1];
            self.resources.items.len -= 1;
            return resource;
        }
        if (self.inline_len != 0) {
            self.inline_len -= 1;
            return self.inline_resources[self.inline_len].?;
        }
        return null;
    }

    fn cleanup(self: *BenchCleanupFrame) usize {
        raw_resource.release_sink = 0;
        while (self.popResource()) |resource| {
            raw_resource.release(resource);
        }
        return raw_resource.release_sink;
    }
};

fn runResourceRawSample(io: std.Io, allocator: std.mem.Allocator, comptime items_per_body: usize, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_resource.current_base = index * items_per_body;
        checksum += preserveValue(try raw_resource.body(allocator, items_per_body));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runResourceEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const ResourceInstance, comptime items_per_body: usize, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_resource.current_base = index * items_per_body;
        raw_resource.acquire_count = 0;
        const body = struct {
            /// Re-enter the current resource handle with a fixed acquire count.
            pub fn body(comptime Cap: type, ctx: anytype) ability.ResetError(NoError)!usize {
                return try effect_resource.body(Cap, ctx, items_per_body);
            }
        };
        checksum += preserveValue(try ability.effect.resource.handle(usize, runtime, instance, effect_resource.manager, body));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runResourceCleanupOnlySample(io: std.Io, allocator: std.mem.Allocator, comptime items_per_body: usize, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        var frame = BenchCleanupFrame.init(allocator);
        defer frame.deinit();
        checksum +%= try frame.fill(index * items_per_body, items_per_body);
        checksum +%= preserveValue(frame.cleanup());
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn printLine(writer: anytype, report: *const LaneReport) !void {
    const raw_stats = summarizeSamples(&report.raw_samples);
    const effect_stats = summarizeSamples(&report.effect_samples);
    const cleanup_stats = summarizeSamples(&report.cleanup_samples);
    try writer.print(
        "items={d} raw_checksum={d} effect_checksum={d} cleanup_checksum={d} raw_median_ns={d} effect_median_ns={d} cleanup_median_ns={d} effect_over_raw={d:.4} cleanup_share={d:.4}\n",
        .{
            report.items_per_body,
            report.raw_checksum,
            report.effect_checksum,
            report.cleanup_checksum,
            raw_stats.median,
            effect_stats.median,
            cleanup_stats.median,
            @as(f64, @floatFromInt(effect_stats.median)) / @as(f64, @floatFromInt(raw_stats.median)),
            @as(f64, @floatFromInt(cleanup_stats.median)) / @as(f64, @floatFromInt(effect_stats.median)),
        },
    );
}

fn runLane(io: std.Io, runtime: *ability.Runtime, instance: *const ResourceInstance, allocator: std.mem.Allocator, comptime items_per_body: usize) !LaneReport {
    _ = try runResourceRawSample(io, allocator, items_per_body, warmup_iterations);
    _ = try runResourceEffectSample(io, runtime, instance, items_per_body, warmup_iterations);
    _ = try runResourceCleanupOnlySample(io, allocator, items_per_body, warmup_iterations);

    var raw_samples = [_]u64{0} ** samples_per_run;
    var effect_samples = [_]u64{0} ** samples_per_run;
    var cleanup_samples = [_]u64{0} ** samples_per_run;
    var raw_checksum: ?usize = null;
    var effect_checksum: ?usize = null;
    var cleanup_checksum: ?usize = null;

    var index: usize = 0;
    while (index < samples_per_run) : (index += 1) {
        const raw_sample = try runResourceRawSample(io, allocator, items_per_body, timed_iterations);
        const effect_sample = try runResourceEffectSample(io, runtime, instance, items_per_body, timed_iterations);
        const cleanup_sample = try runResourceCleanupOnlySample(io, allocator, items_per_body, timed_iterations);

        if (raw_checksum) |checksum| {
            if (checksum != raw_sample.checksum) return error.RawChecksumMismatch;
        } else raw_checksum = raw_sample.checksum;
        if (effect_checksum) |checksum| {
            if (checksum != effect_sample.checksum) return error.EffectChecksumMismatch;
        } else effect_checksum = effect_sample.checksum;
        if (cleanup_checksum) |checksum| {
            if (checksum != cleanup_sample.checksum) return error.CleanupChecksumMismatch;
        } else cleanup_checksum = cleanup_sample.checksum;

        raw_samples[index] = raw_sample.elapsed_ns;
        effect_samples[index] = effect_sample.elapsed_ns;
        cleanup_samples[index] = cleanup_sample.elapsed_ns;
    }

    return .{
        .items_per_body = items_per_body,
        .raw_samples = raw_samples,
        .effect_samples = effect_samples,
        .cleanup_samples = cleanup_samples,
        .raw_checksum = raw_checksum.?,
        .effect_checksum = effect_checksum.?,
        .cleanup_checksum = cleanup_checksum.?,
    };
}

/// Decompose resource-effect acquire and cleanup costs for representative stack depths.
pub fn main(init: std.process.Init) anyerror!void {
    var runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer runtime.deinit();
    var instance = ResourceInstance.init();

    const lane4 = try runLane(init.io, &runtime, &instance, std.heap.smp_allocator, 4);
    const lane32 = try runLane(init.io, &runtime, &instance, std.heap.smp_allocator, 32);

    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "timed_iterations={d} warmup_iterations={d} samples_per_run={d}\n",
        .{ timed_iterations, warmup_iterations, samples_per_run },
    );
    try printLine(stdout, &lane4);
    try printLine(stdout, &lane32);
    try stdout.flush();
}
