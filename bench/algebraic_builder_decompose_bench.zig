const ability = @import("ability");
const std = @import("std");

const NoError = error{};
const timed_iterations: usize = 50_000;
const warmup_iterations: usize = 20_000;
const samples_per_run: usize = 5;
const preserveValue = ability.preserveValue;

const RawTransformPrompt = ability.Prompt(.resume_then_transform, usize, usize, NoError);
const AlgebraicTransformOp = ability.algebraic.TransformOp("algebraic_decompose", usize, usize);

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

const raw_transform = struct {
    var prompt_ptr: ?*const RawTransformPrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Return the current raw transform value into the resumed body.
        pub fn resumeValue() usize {
            return current_value;
        }

        /// Preserve the resumed raw answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn program() ability.Program(RawTransformPrompt) {
        return ability.transformProgram(RawTransformPrompt, usize, handler, struct {
            /// Preserve the raw resumed value plus the benchmark's one-step tail.
            pub fn apply(value: usize) usize {
                return value + 1;
            }
        });
    }
};

const effect_algebraic_transform = struct {
    const no_state = struct {};
    const handler = struct {
        /// Return the payload as the resumptive algebraic transform value.
        pub fn resumeValue(_: no_state, payload: usize) usize {
            return payload;
        }

        /// Preserve the resumed algebraic answer unchanged.
        pub fn afterResume(_: no_state, answer: usize) usize {
            return answer;
        }
    };

    const transform_program = ability.algebraic.Program(usize, NoError, .{AlgebraicTransformOp});
    const transform_configured = transform_program.handlers(.{
        ability.algebraic.handleTransform(AlgebraicTransformOp, no_state{}, handler),
    });
    const empty_program = ability.algebraic.Program(usize, NoError, .{});
    const empty_configured = empty_program.handlers(.{});

    const transform_body = struct {
        const continuation = struct {
            /// Preserve the resumed algebraic value plus the benchmark's one-step tail.
            pub fn apply(value: usize) usize {
                return value + 1;
            }
        };

        /// Execute one algebraic transform operation through the explicit program path.
        pub fn program(ctx: *@TypeOf(transform_configured).Context) @TypeOf(ctx.performProgram(AlgebraicTransformOp, 0, continuation)) {
            return ctx.performProgram(AlgebraicTransformOp, raw_transform.current_value, continuation);
        }
    };

    const empty_body = struct {
        /// Execute the empty configured-run shell with no operations.
        pub fn body(_: *@TypeOf(empty_configured).Context) ability.ResetError(NoError)!usize {
            return raw_transform.current_value + 1;
        }
    };
};

fn runRawTransformSample(io: std.Io, runtime: *ability.Runtime, prompt: *RawTransformPrompt, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_transform.current_value = index;
        checksum += preserveValue(try ability.reset(runtime, prompt, raw_transform.program()));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runConfiguredShellSample(io: std.Io, runtime: *ability.Runtime, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_transform.current_value = index;
        checksum += preserveValue(try effect_algebraic_transform.empty_configured.run(runtime, effect_algebraic_transform.empty_body));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runConfiguredTransformSample(io: std.Io, runtime: *ability.Runtime, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_transform.current_value = index;
        checksum += preserveValue(try effect_algebraic_transform.transform_configured.run(runtime, effect_algebraic_transform.transform_body));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn printLine(writer: anytype, name: []const u8, samples: *const [samples_per_run]u64, checksum: usize) !void {
    const stats = summarizeSamples(samples);
    try writer.print(
        "{s} checksum={d} sample_ns=[{d},{d},{d},{d},{d}] median_ns={d}\n",
        .{
            name,
            checksum,
            samples[0],
            samples[1],
            samples[2],
            samples[3],
            samples[4],
            stats.median,
        },
    );
}

fn medianDelta(later: *const [samples_per_run]u64, earlier: *const [samples_per_run]u64) i64 {
    const later_stats = summarizeSamples(later);
    const earlier_stats = summarizeSamples(earlier);
    return @as(i64, @intCast(later_stats.median)) - @as(i64, @intCast(earlier_stats.median));
}

/// Decompose public algebraic builder overhead into raw, configured-shell, and full-path lanes.
pub fn main(init: std.process.Init) anyerror!void {
    var raw_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer raw_runtime.deinit();
    var raw_prompt = RawTransformPrompt.init();
    raw_transform.prompt_ptr = &raw_prompt;

    var shell_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer shell_runtime.deinit();

    var full_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer full_runtime.deinit();

    _ = try runRawTransformSample(init.io, &raw_runtime, &raw_prompt, warmup_iterations);
    _ = try runConfiguredShellSample(init.io, &shell_runtime, warmup_iterations);
    _ = try runConfiguredTransformSample(init.io, &full_runtime, warmup_iterations);

    var raw_samples = [_]u64{0} ** samples_per_run;
    var shell_samples = [_]u64{0} ** samples_per_run;
    var full_samples = [_]u64{0} ** samples_per_run;

    var raw_checksum: ?usize = null;
    var shell_checksum: ?usize = null;
    var full_checksum: ?usize = null;

    var index: usize = 0;
    while (index < samples_per_run) : (index += 1) {
        const raw_sample = try runRawTransformSample(init.io, &raw_runtime, &raw_prompt, timed_iterations);
        const shell_sample = try runConfiguredShellSample(init.io, &shell_runtime, timed_iterations);
        const full_sample = try runConfiguredTransformSample(init.io, &full_runtime, timed_iterations);

        if (raw_checksum) |checksum| {
            if (checksum != raw_sample.checksum) return error.RawTransformChecksumMismatch;
        } else raw_checksum = raw_sample.checksum;
        if (shell_checksum) |checksum| {
            if (checksum != shell_sample.checksum) return error.ConfiguredShellChecksumMismatch;
        } else shell_checksum = shell_sample.checksum;
        if (full_checksum) |checksum| {
            if (checksum != full_sample.checksum) return error.ConfiguredTransformChecksumMismatch;
        } else full_checksum = full_sample.checksum;

        raw_samples[index] = raw_sample.elapsed_ns;
        shell_samples[index] = shell_sample.elapsed_ns;
        full_samples[index] = full_sample.elapsed_ns;
    }

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "timed_iterations={d} warmup_iterations={d} samples_per_run={d}\n",
        .{ timed_iterations, warmup_iterations, samples_per_run },
    );
    try printLine(stdout, "raw_transform", &raw_samples, raw_checksum.?);
    try printLine(stdout, "configured_run_only", &shell_samples, shell_checksum.?);
    try printLine(stdout, "configured_transform", &full_samples, full_checksum.?);
    try stdout.print(
        "shell_delta_ns={d} perform_delta_ns={d}\n",
        .{
            medianDelta(&shell_samples, &raw_samples),
            medianDelta(&full_samples, &shell_samples),
        },
    );
    try stdout.flush();
}
