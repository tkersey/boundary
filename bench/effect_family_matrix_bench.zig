const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const timed_iterations: usize = 50_000;
const warmup_iterations: usize = 20_000;
const samples_per_run: usize = 5;

const Sample = struct {
    checksum: usize,
    elapsed_ns: u64,
};

const state_target_ratio_max = 1.05;
const reader_target_ratio_max = 1.15;
const opt_ret_ratio_max = 1.50;
const opt_res_ratio_max = 1.20;
const except_ratio_max = 1.20;
const resource_ratio_max = 12.00;
const writer_ratio_max = 20.00;
const resource_items_per_body: usize = 4;
const writer_items_per_body: usize = 16;

const RawStatePrompt = shift.Prompt(.resume_then_transform, usize, usize, NoError);
const ReaderPrompt = shift.Prompt(.resume_then_transform, usize, usize, NoError);
const OptionalReturnPrompt = shift.Prompt(.resume_or_return, usize, usize, NoError);
const OptionalResumePrompt = shift.Prompt(.resume_or_return, usize, usize, NoError);
const ExceptionPrompt = shift.Prompt(.direct_return, usize, usize, NoError);

const StateInstance = shift.effect.state.Instance(usize, NoError);
const ReaderInstance = shift.effect.reader.Instance(usize, NoError);
const OptionalInstance = shift.effect.optional.Instance(usize, NoError);
const ExceptionInstance = shift.effect.exception.Instance(usize, NoError);
const ResourceInstance = shift.effect.resource.Instance(usize, NoError);
const WriterInstance = shift.effect.writer.Instance(usize, NoError);

const raw_state = struct {
    var prompt_ptr: ?*const RawStatePrompt = null;
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

    fn get() shift.ResetError(NoError)!usize {
        return try shift.shift(usize, prompt_ptr.?, get_handle);
    }

    fn set(value: usize) shift.ResetError(NoError)!void {
        pending_state = value;
        _ = try shift.shift(void, prompt_ptr.?, set_handle);
    }

    fn body() shift.ResetError(NoError)!usize {
        const before = try get();
        try set(before + 1);
        return try get();
    }
};

const effect_state = struct {
    /// Execute the state-effect benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!usize {
        const before = try shift.effect.state.get(Cap, ctx);
        try shift.effect.state.set(Cap, ctx, before + 1);
        return try shift.effect.state.get(Cap, ctx);
    }
};

const raw_reader = struct {
    var prompt_ptr: ?*const ReaderPrompt = null;
    var current_env: usize = 0;

    const ask_handle = struct {
        /// Return the current raw benchmark environment into the resumed body.
        pub fn resumeValue() usize {
            return current_env;
        }

        /// Preserve the resumed raw benchmark answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn ask() shift.ResetError(NoError)!usize {
        return try shift.shift(usize, prompt_ptr.?, ask_handle);
    }

    fn body() shift.ResetError(NoError)!usize {
        return (try ask()) + 1;
    }
};

const effect_reader = struct {
    /// Execute the reader-effect benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!usize {
        return (try shift.effect.reader.ask(Cap, ctx)) + 1;
    }
};

const raw_optional_return = struct {
    var prompt_ptr: ?*const OptionalReturnPrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Return immediately from the raw optional benchmark.
        pub fn resumeOrReturn() shift.ResumeOrReturn(usize, usize) {
            return shift.ResumeOrReturn(usize, usize).returnNow(current_value + 1);
        }

        /// Preserve the resumed answer if this branch ever resumes.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn body() shift.ResetError(NoError)!usize {
        _ = try shift.shift(usize, prompt_ptr.?, handler);
        return 0;
    }
};

const effect_optional_return = struct {
    const policy = struct {
        /// Return immediately from the effect optional benchmark.
        pub fn resumeOrReturn() shift.ResumeOrReturn(usize, usize) {
            return shift.ResumeOrReturn(usize, usize).returnNow(raw_optional_return.current_value + 1);
        }

        /// Preserve the resumed answer if this branch ever resumes.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    /// Execute the return-now optional benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!usize {
        _ = try shift.effect.optional.request(Cap, ctx);
        return 0;
    }
};

const raw_optional_resume = struct {
    var prompt_ptr: ?*const OptionalResumePrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Resume once from the raw optional benchmark.
        pub fn resumeOrReturn() shift.ResumeOrReturn(usize, usize) {
            return shift.ResumeOrReturn(usize, usize).resumeWith(current_value);
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn body() shift.ResetError(NoError)!usize {
        const value = try shift.shift(usize, prompt_ptr.?, handler);
        return value + 1;
    }
};

const effect_optional_resume = struct {
    const policy = struct {
        /// Resume once from the effect optional benchmark.
        pub fn resumeOrReturn() shift.ResumeOrReturn(usize, usize) {
            return shift.ResumeOrReturn(usize, usize).resumeWith(raw_optional_resume.current_value);
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    /// Execute the resumptive optional benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!usize {
        const value = try shift.effect.optional.request(Cap, ctx);
        return value + 1;
    }
};

const raw_exception = struct {
    var prompt_ptr: ?*const ExceptionPrompt = null;
    var pending_payload: usize = 0;

    const handler = struct {
        /// Convert the pending payload into the enclosing answer.
        pub fn directReturn() usize {
            return pending_payload;
        }
    };

    fn body() shift.ResetError(NoError)!usize {
        pending_payload += 1;
        _ = try shift.shift(void, prompt_ptr.?, handler);
        return 0;
    }
};

const effect_exception = struct {
    const catcher = struct {
        /// Recover the thrown payload unchanged.
        pub fn directReturn(payload: usize) usize {
            return payload;
        }
    };

    /// Execute the thrown-path exception benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!usize {
        try shift.effect.exception.throw(Cap, ctx, raw_exception.pending_payload + 1);
    }
};

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

    fn body(allocator: std.mem.Allocator) !usize {
        acquire_count = 0;
        release_sink = 0;
        var resources: std.ArrayList(usize) = .empty;
        defer resources.deinit(allocator);
        var checksum: usize = 0;
        var items_remaining = resource_items_per_body;
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
        /// Acquire the next resource value for the bracketed resource benchmark.
        pub fn acquire() usize {
            return raw_resource.acquire();
        }

        /// Release one benchmark resource value.
        pub fn release(resource: usize) void {
            raw_resource.release(resource);
        }
    };

    /// Execute the normal-path resource benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!usize {
        var checksum: usize = 0;
        var items_remaining = resource_items_per_body;
        while (items_remaining != 0) : (items_remaining -= 1) {
            checksum += try shift.effect.resource.acquire(Cap, ctx);
        }
        return checksum;
    }
};

const raw_writer = struct {
    fn body(allocator: std.mem.Allocator) !usize {
        var items: std.ArrayList(usize) = .empty;
        defer items.deinit(allocator);
        var checksum: usize = 0;
        var current: usize = 0;
        while (current < writer_items_per_body) : (current += 1) {
            try items.append(allocator, current + 1);
            checksum += current + 1;
        }
        const owned = try items.toOwnedSlice(allocator);
        defer allocator.free(owned);
        return checksum + owned.len;
    }
};

const effect_writer = struct {
    /// Execute the append-only writer benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!usize {
        var checksum: usize = 0;
        var current: usize = 0;
        while (current < writer_items_per_body) : (current += 1) {
            const item = current + 1;
            try shift.effect.writer.tell(Cap, ctx, item);
            checksum += item;
        }
        return checksum;
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

fn summarizeSamples(values: *const [samples_per_run]u64) struct { min: u64, median: u64, max: u64 } {
    var sorted = values.*;
    sortAscending(&sorted);
    return .{
        .min = sorted[0],
        .median = sorted[sorted.len / 2],
        .max = sorted[sorted.len - 1],
    };
}

fn runStateRawSample(runtime: *shift.Runtime, prompt: *RawStatePrompt, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_state.current_state = index;
        const value = try shift.reset(runtime, prompt, raw_state.body);
        checksum += value + raw_state.current_state;
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runStateEffectSample(runtime: *shift.Runtime, instance: *const StateInstance, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        const result = try shift.effect.state.handle(usize, runtime, instance, index, effect_state);
        checksum += result.value + result.state;
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runReaderRawSample(runtime: *shift.Runtime, prompt: *ReaderPrompt, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_reader.current_env = index;
        checksum += try shift.reset(runtime, prompt, raw_reader.body);
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runReaderEffectSample(runtime: *shift.Runtime, instance: *const ReaderInstance, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        checksum += try shift.effect.reader.handle(usize, runtime, instance, index, effect_reader);
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runOptionalReturnRawSample(runtime: *shift.Runtime, prompt: *OptionalReturnPrompt, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_optional_return.current_value = index;
        checksum += try shift.reset(runtime, prompt, raw_optional_return.body);
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runOptionalReturnEffectSample(runtime: *shift.Runtime, instance: *const OptionalInstance, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_optional_return.current_value = index;
        checksum += try shift.effect.optional.handle(usize, runtime, instance, effect_optional_return.policy, effect_optional_return);
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runOptionalResumeRawSample(runtime: *shift.Runtime, prompt: *OptionalResumePrompt, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_optional_resume.current_value = index;
        checksum += try shift.reset(runtime, prompt, raw_optional_resume.body);
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runOptionalResumeEffectSample(runtime: *shift.Runtime, instance: *const OptionalInstance, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_optional_resume.current_value = index;
        checksum += try shift.effect.optional.handle(usize, runtime, instance, effect_optional_resume.policy, effect_optional_resume);
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runExceptionRawSample(runtime: *shift.Runtime, prompt: *ExceptionPrompt, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_exception.pending_payload = index;
        checksum += try shift.reset(runtime, prompt, raw_exception.body);
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runExceptionEffectSample(runtime: *shift.Runtime, instance: *const ExceptionInstance, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_exception.pending_payload = index;
        checksum += try shift.effect.exception.handle(usize, runtime, instance, effect_exception.catcher, effect_exception);
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runResourceRawSample(allocator: std.mem.Allocator, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_resource.current_base = index * resource_items_per_body;
        checksum += try raw_resource.body(allocator);
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runResourceEffectSample(runtime: *shift.Runtime, instance: *const ResourceInstance, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_resource.current_base = index * resource_items_per_body;
        raw_resource.acquire_count = 0;
        checksum += try shift.effect.resource.handle(usize, runtime, instance, effect_resource.manager, effect_resource);
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runWriterRawSample(allocator: std.mem.Allocator, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        checksum += try raw_writer.body(allocator);
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

fn runWriterEffectSample(runtime: *shift.Runtime, instance: *const WriterInstance, allocator: std.mem.Allocator, iterations: usize) !Sample {
    var timer = try std.time.Timer.start();
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        const result = try shift.effect.writer.handle(usize, usize, runtime, instance, allocator, effect_writer);
        defer allocator.free(result.items);
        checksum += result.value + result.items.len;
    }
    return .{ .checksum = checksum, .elapsed_ns = timer.read() };
}

const LaneReport = struct {
    lane_name: []const u8,
    target_ratio_max: f64,
    raw_samples: *const [samples_per_run]u64,
    effect_samples: *const [samples_per_run]u64,
    raw_checksum: usize,
    effect_checksum: usize,
};

fn printLane(writer: anytype, report: LaneReport) !void {
    const raw_stats = summarizeSamples(report.raw_samples);
    const effect_stats = summarizeSamples(report.effect_samples);
    try writer.print(
        "lane={s} target_ratio_max={d:.2} raw_checksum={d} effect_checksum={d} raw_sample_ns=[{d},{d},{d},{d},{d}] effect_sample_ns=[{d},{d},{d},{d},{d}] raw_min_ns={d} raw_median_ns={d} raw_max_ns={d} effect_min_ns={d} effect_median_ns={d} effect_max_ns={d}\n",
        .{
            report.lane_name,
            report.target_ratio_max,
            report.raw_checksum,
            report.effect_checksum,
            report.raw_samples[0],
            report.raw_samples[1],
            report.raw_samples[2],
            report.raw_samples[3],
            report.raw_samples[4],
            report.effect_samples[0],
            report.effect_samples[1],
            report.effect_samples[2],
            report.effect_samples[3],
            report.effect_samples[4],
            raw_stats.min,
            raw_stats.median,
            raw_stats.max,
            effect_stats.min,
            effect_stats.median,
            effect_stats.max,
        },
    );
}

/// Benchmark every shipped effect family against its chosen comparator lane.
pub fn main() anyerror!void {
    var state_raw_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer state_raw_runtime.deinit();
    var state_raw_prompt = RawStatePrompt.init();
    raw_state.prompt_ptr = &state_raw_prompt;
    var state_effect_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer state_effect_runtime.deinit();
    var state_effect_instance = StateInstance.init();

    var reader_raw_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer reader_raw_runtime.deinit();
    var reader_raw_prompt = ReaderPrompt.init();
    raw_reader.prompt_ptr = &reader_raw_prompt;
    var reader_effect_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer reader_effect_runtime.deinit();
    var reader_effect_instance = ReaderInstance.init();

    var optional_return_raw_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer optional_return_raw_runtime.deinit();
    var optional_return_prompt = OptionalReturnPrompt.init();
    raw_optional_return.prompt_ptr = &optional_return_prompt;
    var optional_return_effect_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer optional_return_effect_runtime.deinit();
    var optional_return_effect_instance = OptionalInstance.init();

    var optional_resume_raw_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer optional_resume_raw_runtime.deinit();
    var optional_resume_prompt = OptionalResumePrompt.init();
    raw_optional_resume.prompt_ptr = &optional_resume_prompt;
    var optional_resume_effect_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer optional_resume_effect_runtime.deinit();
    var optional_resume_effect_instance = OptionalInstance.init();

    var exception_raw_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer exception_raw_runtime.deinit();
    var exception_prompt = ExceptionPrompt.init();
    raw_exception.prompt_ptr = &exception_prompt;
    var exception_effect_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer exception_effect_runtime.deinit();
    var exception_effect_instance = ExceptionInstance.init();

    var resource_effect_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer resource_effect_runtime.deinit();
    var resource_effect_instance = ResourceInstance.init();
    var writer_effect_runtime = shift.Runtime.init(std.heap.smp_allocator, .{});
    defer writer_effect_runtime.deinit();
    var writer_effect_instance = WriterInstance.init();

    _ = try runStateRawSample(&state_raw_runtime, &state_raw_prompt, warmup_iterations);
    _ = try runStateEffectSample(&state_effect_runtime, &state_effect_instance, warmup_iterations);
    _ = try runReaderRawSample(&reader_raw_runtime, &reader_raw_prompt, warmup_iterations);
    _ = try runReaderEffectSample(&reader_effect_runtime, &reader_effect_instance, warmup_iterations);
    _ = try runOptionalReturnRawSample(&optional_return_raw_runtime, &optional_return_prompt, warmup_iterations);
    _ = try runOptionalReturnEffectSample(&optional_return_effect_runtime, &optional_return_effect_instance, warmup_iterations);
    _ = try runOptionalResumeRawSample(&optional_resume_raw_runtime, &optional_resume_prompt, warmup_iterations);
    _ = try runOptionalResumeEffectSample(&optional_resume_effect_runtime, &optional_resume_effect_instance, warmup_iterations);
    _ = try runExceptionRawSample(&exception_raw_runtime, &exception_prompt, warmup_iterations);
    _ = try runExceptionEffectSample(&exception_effect_runtime, &exception_effect_instance, warmup_iterations);
    _ = try runResourceRawSample(std.heap.smp_allocator, warmup_iterations);
    _ = try runResourceEffectSample(&resource_effect_runtime, &resource_effect_instance, warmup_iterations);
    _ = try runWriterRawSample(std.heap.smp_allocator, warmup_iterations);
    _ = try runWriterEffectSample(&writer_effect_runtime, &writer_effect_instance, std.heap.smp_allocator, warmup_iterations);

    var state_raw_samples = [_]u64{0} ** samples_per_run;
    var state_effect_samples = [_]u64{0} ** samples_per_run;
    var reader_raw_samples = [_]u64{0} ** samples_per_run;
    var reader_effect_samples = [_]u64{0} ** samples_per_run;
    var optional_return_raw_samples = [_]u64{0} ** samples_per_run;
    var optional_return_effect_samples = [_]u64{0} ** samples_per_run;
    var optional_resume_raw_samples = [_]u64{0} ** samples_per_run;
    var optional_resume_effect_samples = [_]u64{0} ** samples_per_run;
    var exception_raw_samples = [_]u64{0} ** samples_per_run;
    var exception_effect_samples = [_]u64{0} ** samples_per_run;
    var resource_raw_samples = [_]u64{0} ** samples_per_run;
    var resource_effect_samples = [_]u64{0} ** samples_per_run;
    var writer_raw_samples = [_]u64{0} ** samples_per_run;
    var writer_effect_samples = [_]u64{0} ** samples_per_run;

    var state_raw_checksum: ?usize = null;
    var state_effect_checksum: ?usize = null;
    var reader_raw_checksum: ?usize = null;
    var reader_effect_checksum: ?usize = null;
    var opt_ret_raw_checksum: ?usize = null;
    var opt_ret_effect_checksum: ?usize = null;
    var opt_res_raw_checksum: ?usize = null;
    var opt_res_effect_checksum: ?usize = null;
    var exception_raw_checksum: ?usize = null;
    var exception_effect_checksum: ?usize = null;
    var resource_raw_checksum: ?usize = null;
    var resource_effect_checksum: ?usize = null;
    var writer_raw_checksum: ?usize = null;
    var writer_effect_checksum: ?usize = null;

    var index: usize = 0;
    while (index < samples_per_run) : (index += 1) {
        const state_raw_sample = try runStateRawSample(&state_raw_runtime, &state_raw_prompt, timed_iterations);
        const state_effect_sample = try runStateEffectSample(&state_effect_runtime, &state_effect_instance, timed_iterations);
        const reader_raw_sample = try runReaderRawSample(&reader_raw_runtime, &reader_raw_prompt, timed_iterations);
        const reader_effect_sample = try runReaderEffectSample(&reader_effect_runtime, &reader_effect_instance, timed_iterations);
        const optional_return_raw_sample = try runOptionalReturnRawSample(&optional_return_raw_runtime, &optional_return_prompt, timed_iterations);
        const optional_return_effect_sample = try runOptionalReturnEffectSample(&optional_return_effect_runtime, &optional_return_effect_instance, timed_iterations);
        const optional_resume_raw_sample = try runOptionalResumeRawSample(&optional_resume_raw_runtime, &optional_resume_prompt, timed_iterations);
        const optional_resume_effect_sample = try runOptionalResumeEffectSample(&optional_resume_effect_runtime, &optional_resume_effect_instance, timed_iterations);
        const exception_raw_sample = try runExceptionRawSample(&exception_raw_runtime, &exception_prompt, timed_iterations);
        const exception_effect_sample = try runExceptionEffectSample(&exception_effect_runtime, &exception_effect_instance, timed_iterations);
        const resource_raw_sample = try runResourceRawSample(std.heap.smp_allocator, timed_iterations);
        const resource_effect_sample = try runResourceEffectSample(&resource_effect_runtime, &resource_effect_instance, timed_iterations);
        const writer_raw_sample = try runWriterRawSample(std.heap.smp_allocator, timed_iterations);
        const writer_effect_sample = try runWriterEffectSample(&writer_effect_runtime, &writer_effect_instance, std.heap.smp_allocator, timed_iterations);

        if (state_raw_checksum) |checksum| {
            if (checksum != state_raw_sample.checksum) return error.StateRawChecksumMismatch;
        } else state_raw_checksum = state_raw_sample.checksum;
        if (state_effect_checksum) |checksum| {
            if (checksum != state_effect_sample.checksum) return error.StateEffectChecksumMismatch;
        } else state_effect_checksum = state_effect_sample.checksum;

        if (reader_raw_checksum) |checksum| {
            if (checksum != reader_raw_sample.checksum) return error.ReaderRawChecksumMismatch;
        } else reader_raw_checksum = reader_raw_sample.checksum;
        if (reader_effect_checksum) |checksum| {
            if (checksum != reader_effect_sample.checksum) return error.ReaderEffectChecksumMismatch;
        } else reader_effect_checksum = reader_effect_sample.checksum;

        if (opt_ret_raw_checksum) |checksum| {
            if (checksum != optional_return_raw_sample.checksum) return error.OptionalReturnRawChecksumMismatch;
        } else opt_ret_raw_checksum = optional_return_raw_sample.checksum;
        if (opt_ret_effect_checksum) |checksum| {
            if (checksum != optional_return_effect_sample.checksum) return error.OptionalReturnEffectChecksumMismatch;
        } else opt_ret_effect_checksum = optional_return_effect_sample.checksum;

        if (opt_res_raw_checksum) |checksum| {
            if (checksum != optional_resume_raw_sample.checksum) return error.OptionalResumeRawChecksumMismatch;
        } else opt_res_raw_checksum = optional_resume_raw_sample.checksum;
        if (opt_res_effect_checksum) |checksum| {
            if (checksum != optional_resume_effect_sample.checksum) return error.OptionalResumeEffectChecksumMismatch;
        } else opt_res_effect_checksum = optional_resume_effect_sample.checksum;

        if (exception_raw_checksum) |checksum| {
            if (checksum != exception_raw_sample.checksum) return error.ExceptionRawChecksumMismatch;
        } else exception_raw_checksum = exception_raw_sample.checksum;
        if (exception_effect_checksum) |checksum| {
            if (checksum != exception_effect_sample.checksum) return error.ExceptionEffectChecksumMismatch;
        } else exception_effect_checksum = exception_effect_sample.checksum;

        if (resource_raw_checksum) |checksum| {
            if (checksum != resource_raw_sample.checksum) return error.ResourceRawChecksumMismatch;
        } else resource_raw_checksum = resource_raw_sample.checksum;
        if (resource_effect_checksum) |checksum| {
            if (checksum != resource_effect_sample.checksum) return error.ResourceEffectChecksumMismatch;
        } else resource_effect_checksum = resource_effect_sample.checksum;

        if (writer_raw_checksum) |checksum| {
            if (checksum != writer_raw_sample.checksum) return error.WriterRawChecksumMismatch;
        } else writer_raw_checksum = writer_raw_sample.checksum;
        if (writer_effect_checksum) |checksum| {
            if (checksum != writer_effect_sample.checksum) return error.WriterEffectChecksumMismatch;
        } else writer_effect_checksum = writer_effect_sample.checksum;

        state_raw_samples[index] = state_raw_sample.elapsed_ns;
        state_effect_samples[index] = state_effect_sample.elapsed_ns;
        reader_raw_samples[index] = reader_raw_sample.elapsed_ns;
        reader_effect_samples[index] = reader_effect_sample.elapsed_ns;
        optional_return_raw_samples[index] = optional_return_raw_sample.elapsed_ns;
        optional_return_effect_samples[index] = optional_return_effect_sample.elapsed_ns;
        optional_resume_raw_samples[index] = optional_resume_raw_sample.elapsed_ns;
        optional_resume_effect_samples[index] = optional_resume_effect_sample.elapsed_ns;
        exception_raw_samples[index] = exception_raw_sample.elapsed_ns;
        exception_effect_samples[index] = exception_effect_sample.elapsed_ns;
        resource_raw_samples[index] = resource_raw_sample.elapsed_ns;
        resource_effect_samples[index] = resource_effect_sample.elapsed_ns;
        writer_raw_samples[index] = writer_raw_sample.elapsed_ns;
        writer_effect_samples[index] = writer_effect_sample.elapsed_ns;
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "timed_iterations={d} warmup_iterations={d} samples_per_run={d} lanes=7\n",
        .{ timed_iterations, warmup_iterations, samples_per_run },
    );
    try printLane(stdout, .{ .lane_name = "state", .target_ratio_max = state_target_ratio_max, .raw_samples = &state_raw_samples, .effect_samples = &state_effect_samples, .raw_checksum = state_raw_checksum.?, .effect_checksum = state_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "reader", .target_ratio_max = reader_target_ratio_max, .raw_samples = &reader_raw_samples, .effect_samples = &reader_effect_samples, .raw_checksum = reader_raw_checksum.?, .effect_checksum = reader_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "optional_return_now", .target_ratio_max = opt_ret_ratio_max, .raw_samples = &optional_return_raw_samples, .effect_samples = &optional_return_effect_samples, .raw_checksum = opt_ret_raw_checksum.?, .effect_checksum = opt_ret_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "optional_resume_with", .target_ratio_max = opt_res_ratio_max, .raw_samples = &optional_resume_raw_samples, .effect_samples = &optional_resume_effect_samples, .raw_checksum = opt_res_raw_checksum.?, .effect_checksum = opt_res_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "exception_throw", .target_ratio_max = except_ratio_max, .raw_samples = &exception_raw_samples, .effect_samples = &exception_effect_samples, .raw_checksum = exception_raw_checksum.?, .effect_checksum = exception_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "resource_normal", .target_ratio_max = resource_ratio_max, .raw_samples = &resource_raw_samples, .effect_samples = &resource_effect_samples, .raw_checksum = resource_raw_checksum.?, .effect_checksum = resource_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "writer", .target_ratio_max = writer_ratio_max, .raw_samples = &writer_raw_samples, .effect_samples = &writer_effect_samples, .raw_checksum = writer_raw_checksum.?, .effect_checksum = writer_effect_checksum.? });
    try stdout.flush();
}
