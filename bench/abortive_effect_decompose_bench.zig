const ability = @import("ability");
const std = @import("std");

const NoError = error{};
const timed_iterations: usize = 50_000;
const warmup_iterations: usize = 20_000;
const samples_per_run: usize = 5;
const prelude_items_per_body: usize = 32;
const preserveValue = ability.preserveValue;

const OptionalReturnPrompt = ability.Prompt(.resume_or_return, usize, usize, NoError);
const OptionalResumePrompt = ability.Prompt(.resume_or_return, usize, usize, NoError);
const ExceptionPrompt = ability.Prompt(.direct_return, usize, usize, NoError);

const OptionalInstance = ability.effect.optional.Instance(usize, NoError);
const ExceptionInstance = ability.effect.exception.Instance(usize, NoError);

const Sample = struct {
    checksum: usize,
    elapsed_ns: u64,
};

fn elapsedNsSince(io: std.Io, start: std.Io.Timestamp) u64 {
    return @intCast(start.durationTo(std.Io.Timestamp.now(io, .boot)).toNanoseconds());
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

fn summarizeSamples(values: *const [samples_per_run]u64) struct { median: u64 } {
    var sorted = values.*;
    sortAscending(&sorted);
    return .{ .median = sorted[sorted.len / 2] };
}

const raw_optional_return = struct {
    var prompt_ptr: ?*const OptionalReturnPrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Return immediately with the current synthetic payload.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).returnNow(current_value);
        }

        /// Preserve any resumed answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn body() ability.ResetError(NoError)!usize {
        var checksum: usize = 0;
        var current: usize = 0;
        while (current < prelude_items_per_body) : (current += 1) {
            checksum +%= current_value + current + 1;
        }
        _ = try ability.frontend.choice(usize, prompt_ptr.?, handler);
        return checksum;
    }
};

const effect_optional_return = struct {
    const policy = struct {
        /// Return immediately with the current synthetic payload.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).returnNow(raw_optional_return.current_value);
        }

        /// Preserve any resumed answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    /// Execute the heavier return-now optional lane.
    pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.optional.requestProgram(Cap, ctx, struct {
        /// Recompute the prelude checksum if the optional request unexpectedly resumes.
        pub fn apply(_: usize) usize {
            var checksum: usize = 0;
            var current: usize = 0;
            while (current < prelude_items_per_body) : (current += 1) {
                checksum +%= raw_optional_return.current_value + current + 1;
            }
            return checksum;
        }
    })) {
        return ability.effect.optional.requestProgram(Cap, ctx, struct {
            /// Recompute the prelude checksum if the optional request unexpectedly resumes.
            pub fn apply(_: usize) usize {
                var inner_checksum: usize = 0;
                var inner_current: usize = 0;
                while (inner_current < prelude_items_per_body) : (inner_current += 1) {
                    inner_checksum +%= raw_optional_return.current_value + inner_current + 1;
                }
                return inner_checksum;
            }
        });
    }
};

const raw_optional_resume = struct {
    var prompt_ptr: ?*const OptionalResumePrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Resume once with the current synthetic payload.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).resumeWith(current_value);
        }

        /// Preserve any resumed answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn body() ability.ResetError(NoError)!usize {
        const value = try ability.frontend.choice(usize, prompt_ptr.?, handler);
        var checksum: usize = value;
        var current: usize = 0;
        while (current < prelude_items_per_body) : (current += 1) {
            checksum +%= current_value + current + 1;
        }
        return checksum;
    }
};

const effect_optional_resume = struct {
    const policy = struct {
        /// Resume once with the current synthetic payload.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).resumeWith(raw_optional_resume.current_value);
        }

        /// Preserve any resumed answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    /// Execute the heavier resumptive optional lane.
    pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.optional.requestProgram(Cap, ctx, struct {
        /// Resume and add the amortized prelude checksum to the resumed value.
        pub fn apply(value: usize) usize {
            var checksum: usize = value;
            var current: usize = 0;
            while (current < prelude_items_per_body) : (current += 1) {
                checksum +%= raw_optional_resume.current_value + current + 1;
            }
            return checksum;
        }
    })) {
        return ability.effect.optional.requestProgram(Cap, ctx, struct {
            /// Resume and add the amortized prelude checksum to the resumed value.
            pub fn apply(value: usize) usize {
                var checksum: usize = value;
                var current: usize = 0;
                while (current < prelude_items_per_body) : (current += 1) {
                    checksum +%= raw_optional_resume.current_value + current + 1;
                }
                return checksum;
            }
        });
    }
};

const raw_exception = struct {
    var prompt_ptr: ?*const ExceptionPrompt = null;
    var pending_payload: usize = 0;

    const handler = struct {
        /// Return the pending payload through the raw direct-return handler.
        pub fn directReturn() usize {
            return pending_payload;
        }
    };

    fn body() ability.ResetError(NoError)!usize {
        var checksum: usize = 0;
        var current: usize = 0;
        while (current < prelude_items_per_body) : (current += 1) {
            checksum +%= pending_payload + current;
        }
        try ability.frontend.abort(prompt_ptr.?, handler);
        return checksum;
    }
};

const effect_exception = struct {
    const catcher = struct {
        /// Preserve the thrown payload unchanged.
        pub fn directReturn(payload: usize) usize {
            return payload;
        }
    };

    /// Execute the heavier thrown-path exception lane.
    pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.exception.throwProgram(Cap, ctx, raw_exception.pending_payload)) {
        var checksum: usize = 0;
        var current: usize = 0;
        while (current < prelude_items_per_body) : (current += 1) {
            checksum +%= raw_exception.pending_payload + current;
        }
        return ability.effect.exception.throwProgram(Cap, ctx, raw_exception.pending_payload + checksum);
    }
};

fn runOptionalReturnRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *OptionalReturnPrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runOptionalReturnEffectSample(io, runtime, &OptionalInstance.init(), iterations);
}

fn runOptionalReturnEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const OptionalInstance, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_optional_return.current_value = index;
        checksum += preserveValue(try ability.effect.optional.handle(usize, runtime, instance, effect_optional_return.policy, effect_optional_return));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runOptionalResumeRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *OptionalResumePrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runOptionalResumeEffectSample(io, runtime, &OptionalInstance.init(), iterations);
}

fn runOptionalResumeEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const OptionalInstance, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_optional_resume.current_value = index;
        checksum += preserveValue(try ability.effect.optional.handle(usize, runtime, instance, effect_optional_resume.policy, effect_optional_resume));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runExceptionRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *ExceptionPrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runExceptionEffectSample(io, runtime, &ExceptionInstance.init(), iterations);
}

fn runExceptionEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const ExceptionInstance, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_exception.pending_payload = index;
        checksum += preserveValue(try ability.effect.exception.handle(usize, runtime, instance, effect_exception.catcher, effect_exception));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn printLine(writer: anytype, name: []const u8, raw_samples: *const [samples_per_run]u64, effect_samples: *const [samples_per_run]u64, raw_checksum: usize, effect_checksum: usize) !void {
    const raw_stats = summarizeSamples(raw_samples);
    const effect_stats = summarizeSamples(effect_samples);
    try writer.print(
        "lane={s} raw_checksum={d} effect_checksum={d} raw_median_ns={d} effect_median_ns={d} ratio={d:.4}\n",
        .{
            name,
            raw_checksum,
            effect_checksum,
            raw_stats.median,
            effect_stats.median,
            @as(f64, @floatFromInt(effect_stats.median)) / @as(f64, @floatFromInt(raw_stats.median)),
        },
    );
}

/// Decompose heavier optional and exception abortive paths for acceptance decisions.
pub fn main(init: std.process.Init) anyerror!void {
    var optional_return_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer optional_return_runtime.deinit();
    var optional_return_prompt = OptionalReturnPrompt.init();
    raw_optional_return.prompt_ptr = &optional_return_prompt;
    var optional_return_instance = OptionalInstance.init();

    var optional_resume_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer optional_resume_runtime.deinit();
    var optional_resume_prompt = OptionalResumePrompt.init();
    raw_optional_resume.prompt_ptr = &optional_resume_prompt;
    var optional_resume_instance = OptionalInstance.init();

    var exception_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer exception_runtime.deinit();
    var exception_prompt = ExceptionPrompt.init();
    raw_exception.prompt_ptr = &exception_prompt;
    var exception_instance = ExceptionInstance.init();

    _ = try runOptionalReturnRawSample(init.io, &optional_return_runtime, &optional_return_prompt, warmup_iterations);
    _ = try runOptionalReturnEffectSample(init.io, &optional_return_runtime, &optional_return_instance, warmup_iterations);
    _ = try runOptionalResumeRawSample(init.io, &optional_resume_runtime, &optional_resume_prompt, warmup_iterations);
    _ = try runOptionalResumeEffectSample(init.io, &optional_resume_runtime, &optional_resume_instance, warmup_iterations);
    _ = try runExceptionRawSample(init.io, &exception_runtime, &exception_prompt, warmup_iterations);
    _ = try runExceptionEffectSample(init.io, &exception_runtime, &exception_instance, warmup_iterations);

    var opt_ret_raw_samples = [_]u64{0} ** samples_per_run;
    var opt_ret_eff_samples = [_]u64{0} ** samples_per_run;
    var opt_res_raw_samples = [_]u64{0} ** samples_per_run;
    var opt_res_eff_samples = [_]u64{0} ** samples_per_run;
    var exn_raw_samples = [_]u64{0} ** samples_per_run;
    var exn_eff_samples = [_]u64{0} ** samples_per_run;

    var opt_ret_raw_checksum: ?usize = null;
    var opt_ret_eff_checksum: ?usize = null;
    var opt_res_raw_checksum: ?usize = null;
    var opt_res_eff_checksum: ?usize = null;
    var exn_raw_checksum: ?usize = null;
    var exn_eff_checksum: ?usize = null;

    var index: usize = 0;
    while (index < samples_per_run) : (index += 1) {
        const opt_ret_raw = try runOptionalReturnRawSample(init.io, &optional_return_runtime, &optional_return_prompt, timed_iterations);
        const opt_ret_eff = try runOptionalReturnEffectSample(init.io, &optional_return_runtime, &optional_return_instance, timed_iterations);
        const opt_res_raw = try runOptionalResumeRawSample(init.io, &optional_resume_runtime, &optional_resume_prompt, timed_iterations);
        const opt_res_eff = try runOptionalResumeEffectSample(init.io, &optional_resume_runtime, &optional_resume_instance, timed_iterations);
        const exn_raw = try runExceptionRawSample(init.io, &exception_runtime, &exception_prompt, timed_iterations);
        const exn_eff = try runExceptionEffectSample(init.io, &exception_runtime, &exception_instance, timed_iterations);

        if (opt_ret_raw_checksum) |checksum| {
            if (checksum != opt_ret_raw.checksum) return error.OptionalReturnRawChecksumMismatch;
        } else opt_ret_raw_checksum = opt_ret_raw.checksum;
        if (opt_ret_eff_checksum) |checksum| {
            if (checksum != opt_ret_eff.checksum) return error.OptionalReturnEffectChecksumMismatch;
        } else opt_ret_eff_checksum = opt_ret_eff.checksum;
        if (opt_res_raw_checksum) |checksum| {
            if (checksum != opt_res_raw.checksum) return error.OptionalResumeRawChecksumMismatch;
        } else opt_res_raw_checksum = opt_res_raw.checksum;
        if (opt_res_eff_checksum) |checksum| {
            if (checksum != opt_res_eff.checksum) return error.OptionalResumeEffectChecksumMismatch;
        } else opt_res_eff_checksum = opt_res_eff.checksum;
        if (exn_raw_checksum) |checksum| {
            if (checksum != exn_raw.checksum) return error.ExceptionRawChecksumMismatch;
        } else exn_raw_checksum = exn_raw.checksum;
        if (exn_eff_checksum) |checksum| {
            if (checksum != exn_eff.checksum) return error.ExceptionEffectChecksumMismatch;
        } else exn_eff_checksum = exn_eff.checksum;

        opt_ret_raw_samples[index] = opt_ret_raw.elapsed_ns;
        opt_ret_eff_samples[index] = opt_ret_eff.elapsed_ns;
        opt_res_raw_samples[index] = opt_res_raw.elapsed_ns;
        opt_res_eff_samples[index] = opt_res_eff.elapsed_ns;
        exn_raw_samples[index] = exn_raw.elapsed_ns;
        exn_eff_samples[index] = exn_eff.elapsed_ns;
    }

    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "timed_iterations={d} warmup_iterations={d} samples_per_run={d} prelude_items_per_body={d}\n",
        .{ timed_iterations, warmup_iterations, samples_per_run, prelude_items_per_body },
    );
    try printLine(stdout, "optional_return_now_prelude32", &opt_ret_raw_samples, &opt_ret_eff_samples, opt_ret_raw_checksum.?, opt_ret_eff_checksum.?);
    try printLine(stdout, "optional_resume_with_batch32", &opt_res_raw_samples, &opt_res_eff_samples, opt_res_raw_checksum.?, opt_res_eff_checksum.?);
    try printLine(stdout, "exception_throw_prelude32", &exn_raw_samples, &exn_eff_samples, exn_raw_checksum.?, exn_eff_checksum.?);
    try stdout.flush();
}
