const ability = @import("ability");
const std = @import("std");

const NoError = error{};
const RawPrompt = ability.Prompt(.resume_then_transform, usize, usize, NoError);
const StateInstance = ability.effect.state.Instance(usize, NoError);
const timed_iterations: usize = 50_000;
const warmup_iterations: usize = 20_000;
const samples_per_run: usize = 5;

const Sample = struct {
    checksum: usize,
    elapsed_ns: u64,
};

fn elapsedNsSince(io: std.Io, start: std.Io.Timestamp) u64 {
    return @intCast(start.durationTo(std.Io.Timestamp.now(io, .boot)).toNanoseconds());
}

fn preserveValue(value: anytype) @TypeOf(value) {
    const preserved = value;
    std.mem.doNotOptimizeAway(preserved);
    return preserved;
}

fn rawProgram(comptime PromptType: type, body: anytype) ability.frontend.Program(PromptType) {
    return ability.frontend.computeProgram(PromptType, body);
}

const raw_reset_only = struct {
    var current: usize = 0;

    fn body() ability.ResetError(NoError)!usize {
        return current;
    }
};

const raw_state = struct {
    var prompt_ptr: ?*const RawPrompt = null;
    var current_state: usize = 0;
    var pending_state: usize = 0;

    const get_handle = struct {
        /// Return the current raw benchmark state into the resumed body.
        pub fn resumeValue() usize {
            return current_state;
        }

        /// Preserve the resumed raw benchmark answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    const set_handle = struct {
        /// Update the raw benchmark state before resuming the body.
        pub fn resumeValue() void {
            current_state = pending_state;
        }

        /// Preserve the resumed raw benchmark answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn get() ability.ResetError(NoError)!usize {
        return try ability.frontend.transform(usize, prompt_ptr.?, get_handle);
    }

    fn set(value: usize) ability.ResetError(NoError)!void {
        pending_state = value;
        _ = try ability.frontend.transform(void, prompt_ptr.?, set_handle);
    }

    fn body() ability.ResetError(NoError)!usize {
        const before = try get();
        try set(before + 1);
        return try get();
    }
};

const effect_state = struct {
    /// Execute the state-effect benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype) ability.ResetError(NoError)!usize {
        const before = try ability.effect.state.get(Cap, ctx);
        try ability.effect.state.set(Cap, ctx, before + 1);
        return try ability.effect.state.get(Cap, ctx);
    }
};

const effect_passthrough = struct {
    /// Execute the passthrough state-effect benchmark body.
    pub fn body(comptime Cap: type, _: anytype) ability.ResetError(NoError)!usize {
        _ = Cap;
        return 1;
    }
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

fn runRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *RawPrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runEffectSample(io, runtime, &StateInstance.init(), iterations);
}

fn runRawResetOnlySample(io: std.Io, runtime: *ability.Runtime, prompt: *RawPrompt, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;

    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_reset_only.current = index;
        checksum += preserveValue(try ability.reset(runtime, prompt, rawProgram(RawPrompt, raw_reset_only.body)));
    }

    return .{
        .checksum = checksum,
        .elapsed_ns = elapsedNsSince(io, start),
    };
}

fn runEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const StateInstance, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;

    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        const result = preserveValue(try ability.effect.state.handle(usize, runtime, instance, index, effect_state));
        checksum += result.value + result.state;
    }

    return .{
        .checksum = checksum,
        .elapsed_ns = elapsedNsSince(io, start),
    };
}

fn runEffectPassthroughSample(io: std.Io, runtime: *ability.Runtime, instance: *const StateInstance, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;

    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        const result = preserveValue(try ability.effect.state.handle(usize, runtime, instance, index, effect_passthrough));
        checksum += result.value + result.state;
    }

    return .{
        .checksum = checksum,
        .elapsed_ns = elapsedNsSince(io, start),
    };
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

/// Compare raw prompt-based state handling against the additive effect wrapper.
pub fn main(init: std.process.Init) anyerror!void {
    var raw_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer raw_runtime.deinit();
    var raw_prompt = RawPrompt.init();
    raw_state.prompt_ptr = &raw_prompt;

    var effect_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer effect_runtime.deinit();
    var effect_instance = StateInstance.init();

    _ = try runRawSample(init.io, &raw_runtime, &raw_prompt, warmup_iterations);
    _ = try runRawResetOnlySample(init.io, &raw_runtime, &raw_prompt, warmup_iterations);
    _ = try runEffectSample(init.io, &effect_runtime, &effect_instance, warmup_iterations);
    _ = try runEffectPassthroughSample(init.io, &effect_runtime, &effect_instance, warmup_iterations);

    var raw_samples = [_]u64{0} ** samples_per_run;
    var raw_reset_only_samples = [_]u64{0} ** samples_per_run;
    var effect_samples = [_]u64{0} ** samples_per_run;
    var effect_passthrough_samples = [_]u64{0} ** samples_per_run;
    var raw_checksum: ?usize = null;
    var raw_reset_only_checksum: ?usize = null;
    var effect_checksum: ?usize = null;
    var effect_passthrough_checksum: ?usize = null;

    var index: usize = 0;
    while (index < samples_per_run) : (index += 1) {
        const raw_sample = try runRawSample(init.io, &raw_runtime, &raw_prompt, timed_iterations);
        const raw_reset_only_sample = try runRawResetOnlySample(init.io, &raw_runtime, &raw_prompt, timed_iterations);
        const effect_sample = try runEffectSample(init.io, &effect_runtime, &effect_instance, timed_iterations);
        const effect_passthrough_sample = try runEffectPassthroughSample(init.io, &effect_runtime, &effect_instance, timed_iterations);

        if (raw_checksum) |checksum| {
            if (checksum != raw_sample.checksum) return error.RawChecksumMismatch;
        } else {
            raw_checksum = raw_sample.checksum;
        }

        if (effect_checksum) |checksum| {
            if (checksum != effect_sample.checksum) return error.EffectChecksumMismatch;
        } else {
            effect_checksum = effect_sample.checksum;
        }

        if (raw_reset_only_checksum) |checksum| {
            if (checksum != raw_reset_only_sample.checksum) return error.RawResetOnlyChecksumMismatch;
        } else {
            raw_reset_only_checksum = raw_reset_only_sample.checksum;
        }

        if (effect_passthrough_checksum) |checksum| {
            if (checksum != effect_passthrough_sample.checksum) return error.EffectPassthroughChecksumMismatch;
        } else {
            effect_passthrough_checksum = effect_passthrough_sample.checksum;
        }

        if (raw_sample.checksum != effect_sample.checksum) return error.BenchmarkParityMismatch;

        raw_samples[index] = raw_sample.elapsed_ns;
        raw_reset_only_samples[index] = raw_reset_only_sample.elapsed_ns;
        effect_samples[index] = effect_sample.elapsed_ns;
        effect_passthrough_samples[index] = effect_passthrough_sample.elapsed_ns;
    }

    const raw_stats = summarizeSamples(&raw_samples);
    const raw_reset_only_stats = summarizeSamples(&raw_reset_only_samples);
    const effect_stats = summarizeSamples(&effect_samples);
    const effect_passthrough_stats = summarizeSamples(&effect_passthrough_samples);

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "timed_iterations={d} warmup_iterations={d} samples_per_run={d} raw_checksum={d} raw_reset_only_checksum={d} effect_checksum={d} effect_passthrough_checksum={d}\n",
        .{
            timed_iterations,
            warmup_iterations,
            samples_per_run,
            raw_checksum.?,
            raw_reset_only_checksum.?,
            effect_checksum.?,
            effect_passthrough_checksum.?,
        },
    );
    try stdout.print(
        "raw_sample_ns=[{d},{d},{d},{d},{d}] raw_min_ns={d} raw_median_ns={d} raw_max_ns={d}\n",
        .{
            raw_samples[0],
            raw_samples[1],
            raw_samples[2],
            raw_samples[3],
            raw_samples[4],
            raw_stats.min,
            raw_stats.median,
            raw_stats.max,
        },
    );
    try stdout.print(
        "raw_reset_only_sample_ns=[{d},{d},{d},{d},{d}] raw_reset_only_min_ns={d} raw_reset_only_median_ns={d} raw_reset_only_max_ns={d}\n",
        .{
            raw_reset_only_samples[0],
            raw_reset_only_samples[1],
            raw_reset_only_samples[2],
            raw_reset_only_samples[3],
            raw_reset_only_samples[4],
            raw_reset_only_stats.min,
            raw_reset_only_stats.median,
            raw_reset_only_stats.max,
        },
    );
    try stdout.print(
        "effect_sample_ns=[{d},{d},{d},{d},{d}] effect_min_ns={d} effect_median_ns={d} effect_max_ns={d}\n",
        .{
            effect_samples[0],
            effect_samples[1],
            effect_samples[2],
            effect_samples[3],
            effect_samples[4],
            effect_stats.min,
            effect_stats.median,
            effect_stats.max,
        },
    );
    try stdout.print(
        "effect_passthrough_sample_ns=[{d},{d},{d},{d},{d}] effect_passthrough_min_ns={d} effect_passthrough_median_ns={d} effect_passthrough_max_ns={d}\n",
        .{
            effect_passthrough_samples[0],
            effect_passthrough_samples[1],
            effect_passthrough_samples[2],
            effect_passthrough_samples[3],
            effect_passthrough_samples[4],
            effect_passthrough_stats.min,
            effect_passthrough_stats.median,
            effect_passthrough_stats.max,
        },
    );
    try stdout.flush();
}
