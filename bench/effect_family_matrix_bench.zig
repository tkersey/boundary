const ability = @import("ability");
const std = @import("std");

const NoError = error{};
const timed_iterations: usize = 50_000;
const warmup_iterations: usize = 20_000;
const samples_per_run: usize = 9;
const preserveValue = ability.preserveValue;

const Sample = struct {
    checksum: usize,
    elapsed_ns: u64,
};

fn elapsedNsSince(io: std.Io, start: std.Io.Timestamp) u64 {
    return @intCast(start.durationTo(std.Io.Timestamp.now(io, .boot)).toNanoseconds());
}

const state_micro_target_ratio_max = 1.05;
const reader_micro_target_ratio_max = 1.15;
const reader_batch_target_ratio_max = 1.10;
const opt_ret_micro_ratio_max = 1.50;
const opt_ret_pre_ratio_max = 1.50;
const opt_res_micro_ratio_max = 1.25;
const opt_res_batch_ratio_max = 1.25;
const exn_micro_ratio_max = 1.30;
const exn_pre_ratio_max = 1.25;
const alg_transform_micro_max = 1.40;
const alg_choice_micro_max = 1.65;
const alg_abort_micro_max = 1.60;
const resource4_target_ratio_max = 3.50;
const resource32_target_ratio_max = 4.00;
const writer_micro_target_ratio_max = 1.50;
const writer16_target_ratio_max = 2.25;
const writer64_target_ratio_max = 3.25;

const reader_items_per_body: usize = 8;
const prelude_items_per_body: usize = 8;
const resource_small_items_per_body: usize = 4;
const resource_large_items_per_body: usize = 32;
const writer_small_items_per_body: usize = 16;
const writer_large_items_per_body: usize = 64;

const RawStatePrompt = ability.Prompt(.resume_then_transform, usize, usize, NoError);
const ReaderPrompt = ability.Prompt(.resume_then_transform, usize, usize, NoError);
const OptionalReturnPrompt = ability.Prompt(.resume_or_return, usize, usize, NoError);
const OptionalResumePrompt = ability.Prompt(.resume_or_return, usize, usize, NoError);
const ExceptionPrompt = ability.Prompt(.direct_return, usize, usize, NoError);
const AlgebraicTransformPrompt = ability.Prompt(.resume_then_transform, usize, usize, NoError);
const AlgebraicChoicePrompt = ability.Prompt(.resume_or_return, usize, usize, NoError);
const AlgebraicAbortPrompt = ability.Prompt(.direct_return, usize, usize, NoError);

const StateInstance = ability.effect.state.Instance(usize, NoError);
const ReaderInstance = ability.effect.reader.Instance(usize, NoError);
const OptionalInstance = ability.effect.optional.Instance(usize, NoError);
const ExceptionInstance = ability.effect.exception.Instance(usize, NoError);
const ResourceInstance = ability.effect.resource.Instance(usize, NoError);
const WriterInstance = ability.effect.writer.Instance(usize, NoError);
const AlgebraicTransformOp = ability.algebraic.TransformOp("algebraic_transform_micro", usize, usize);
const AlgebraicChoiceOp = ability.algebraic.ChoiceOp("algebraic_choice_micro", usize, usize);
const AlgebraicAbortOp = ability.algebraic.AbortOp("algebraic_abort_micro", usize);

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
    /// Execute the state-effect micro benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype) ability.ResetError(NoError)!usize {
        const before = try ability.effect.state.get(Cap, ctx);
        try ability.effect.state.set(Cap, ctx, before + 1);
        return try ability.effect.state.get(Cap, ctx);
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

    fn ask() ability.ResetError(NoError)!usize {
        return try ability.frontend.transform(usize, prompt_ptr.?, ask_handle);
    }

    fn body() ability.ResetError(NoError)!usize {
        return (try ask()) + 1;
    }
};

const effect_reader_micro = struct {
    /// Execute the reader-effect micro benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype) ability.ResetError(NoError)!usize {
        return (try ability.effect.reader.ask(Cap, ctx)) + 1;
    }
};

const raw_reader_batch = struct {
    var prompt_ptr: ?*const ReaderPrompt = null;
    var current_env: usize = 0;

    const ask_handle = struct {
        /// Return the current batch benchmark environment into the resumed body.
        pub fn resumeValue() usize {
            return current_env;
        }

        /// Preserve the resumed raw batch answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn ask() ability.ResetError(NoError)!usize {
        return try ability.frontend.transform(usize, prompt_ptr.?, ask_handle);
    }

    fn body() ability.ResetError(NoError)!usize {
        var checksum: usize = 0;
        var current: usize = 0;
        while (current < reader_items_per_body) : (current += 1) {
            checksum += try ask();
        }
        return checksum;
    }
};

const effect_reader_batch = struct {
    /// Execute the reader-effect amortized benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype) ability.ResetError(NoError)!usize {
        var checksum: usize = 0;
        var current: usize = 0;
        while (current < reader_items_per_body) : (current += 1) {
            checksum += try ability.effect.reader.ask(Cap, ctx);
        }
        return checksum;
    }
};

const raw_optional_return = struct {
    var prompt_ptr: ?*const OptionalReturnPrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Return immediately from the raw optional benchmark.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).returnNow(current_value + 1);
        }

        /// Preserve the resumed answer if this branch ever resumes.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn body() ability.ResetError(NoError)!usize {
        _ = try ability.frontend.choice(usize, prompt_ptr.?, handler);
        return 0;
    }
};

const effect_optional_return_micro = struct {
    const policy = struct {
        /// Return immediately from the effect optional benchmark.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).returnNow(raw_optional_return.current_value + 1);
        }

        /// Preserve the resumed answer if this branch ever resumes.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    /// Execute the return-now optional micro benchmark body.
    pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.optional.requestProgram(Cap, ctx, struct {
        /// Return the direct-answer branch if the request unexpectedly resumes.
        pub fn apply(_: usize) usize {
            return 0;
        }
    })) {
        return ability.effect.optional.requestProgram(Cap, ctx, struct {
            /// Return the direct-answer branch if the request unexpectedly resumes.
            pub fn apply(_: usize) usize {
                return 0;
            }
        });
    }
};

const raw_optional_return_prelude = struct {
    var prompt_ptr: ?*const OptionalReturnPrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Return immediately after the amortized prelude.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).returnNow(current_value);
        }

        /// Preserve the resumed answer if this branch ever resumes.
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

const effect_optional_return_prelude = struct {
    const policy = struct {
        /// Return immediately after the amortized prelude.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).returnNow(raw_optional_return_prelude.current_value);
        }

        /// Preserve the resumed answer if this branch ever resumes.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    /// Execute the return-now amortized benchmark body.
    pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.optional.requestProgram(Cap, ctx, struct {
        /// Recompute the amortized prelude checksum if the request unexpectedly resumes.
        pub fn apply(_: usize) usize {
            var checksum: usize = 0;
            var current: usize = 0;
            while (current < prelude_items_per_body) : (current += 1) {
                checksum +%= raw_optional_return_prelude.current_value + current + 1;
            }
            return checksum;
        }
    })) {
        return ability.effect.optional.requestProgram(Cap, ctx, struct {
            /// Recompute the amortized prelude checksum if the request unexpectedly resumes.
            pub fn apply(_: usize) usize {
                var checksum: usize = 0;
                var current: usize = 0;
                while (current < prelude_items_per_body) : (current += 1) {
                    checksum +%= raw_optional_return_prelude.current_value + current + 1;
                }
                return checksum;
            }
        });
    }
};

const raw_optional_resume = struct {
    var prompt_ptr: ?*const OptionalResumePrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Resume once from the raw optional benchmark.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).resumeWith(current_value);
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn body() ability.ResetError(NoError)!usize {
        const value = try ability.frontend.choice(usize, prompt_ptr.?, handler);
        return value + 1;
    }
};

const effect_optional_resume_micro = struct {
    const policy = struct {
        /// Resume once from the effect optional benchmark.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).resumeWith(raw_optional_resume.current_value);
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    /// Execute the resumptive optional micro benchmark body.
    pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.optional.requestProgram(Cap, ctx, struct {
        /// Increment the resumed optional value for the micro lane.
        pub fn apply(value: usize) usize {
            return value + 1;
        }
    })) {
        return ability.effect.optional.requestProgram(Cap, ctx, struct {
            /// Increment the resumed optional value for the micro lane.
            pub fn apply(value: usize) usize {
                return value + 1;
            }
        });
    }
};

const raw_optional_resume_batch = struct {
    var prompt_ptr: ?*const OptionalResumePrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Resume once from the amortized raw optional benchmark.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).resumeWith(current_value);
        }

        /// Preserve the resumed answer unchanged.
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

const effect_optional_resume_batch = struct {
    const policy = struct {
        /// Resume once from the amortized effect optional benchmark.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).resumeWith(raw_optional_resume_batch.current_value);
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    /// Execute the resumptive amortized optional benchmark body.
    pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.optional.requestProgram(Cap, ctx, struct {
        /// Add the amortized prelude checksum to the resumed optional value.
        pub fn apply(value: usize) usize {
            var checksum: usize = value;
            var current: usize = 0;
            while (current < prelude_items_per_body) : (current += 1) {
                checksum +%= raw_optional_resume_batch.current_value + current + 1;
            }
            return checksum;
        }
    })) {
        return ability.effect.optional.requestProgram(Cap, ctx, struct {
            /// Add the amortized prelude checksum to the resumed optional value.
            pub fn apply(value: usize) usize {
                var checksum: usize = value;
                var current: usize = 0;
                while (current < prelude_items_per_body) : (current += 1) {
                    checksum +%= raw_optional_resume_batch.current_value + current + 1;
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
        /// Convert the pending payload into the enclosing answer.
        pub fn directReturn() usize {
            return pending_payload;
        }
    };

    fn body() ability.ResetError(NoError)!usize {
        pending_payload += 1;
        try ability.frontend.abort(prompt_ptr.?, handler);
        return 0;
    }
};

const effect_exception_micro = struct {
    const catcher = struct {
        /// Recover the thrown payload unchanged.
        pub fn directReturn(payload: usize) usize {
            return payload;
        }
    };

    /// Execute the thrown-path exception micro benchmark body.
    pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.exception.throwProgram(Cap, ctx, raw_exception.pending_payload + 1)) {
        return ability.effect.exception.throwProgram(Cap, ctx, raw_exception.pending_payload + 1);
    }
};

const raw_exception_prelude = struct {
    var prompt_ptr: ?*const ExceptionPrompt = null;
    var pending_payload: usize = 0;

    const handler = struct {
        /// Convert the pending payload into the enclosing answer.
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

const effect_exception_prelude = struct {
    const catcher = struct {
        /// Recover the thrown payload unchanged.
        pub fn directReturn(payload: usize) usize {
            return payload;
        }
    };

    /// Execute the amortized thrown-path exception benchmark body.
    pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.exception.throwProgram(Cap, ctx, raw_exception_prelude.pending_payload)) {
        var checksum: usize = 0;
        var current: usize = 0;
        while (current < prelude_items_per_body) : (current += 1) {
            checksum +%= raw_exception_prelude.pending_payload + current;
        }
        return ability.effect.exception.throwProgram(Cap, ctx, raw_exception_prelude.pending_payload + checksum);
    }
};

const raw_algebraic_transform = struct {
    var prompt_ptr: ?*const AlgebraicTransformPrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Return the current raw algebraic transform value into the resumed body.
        pub fn resumeValue() usize {
            return current_value;
        }

        /// Preserve the resumed raw algebraic transform answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn body() ability.ResetError(NoError)!usize {
        const value = try ability.frontend.transform(usize, prompt_ptr.?, handler);
        return value + 1;
    }
};

const effect_algebraic_transform = struct {
    const no_state = struct {};
    const handler = struct {
        /// Return the payload as the resumptive transform value.
        pub fn resumeValue(_: no_state, payload: usize) usize {
            return payload;
        }

        /// Preserve the resumed transform answer unchanged.
        pub fn afterResume(_: no_state, answer: usize) usize {
            return answer;
        }
    };
    const program = ability.algebraic.Program(usize, NoError, .{AlgebraicTransformOp});
    const configured = program.handlers(.{
        ability.algebraic.handleTransform(AlgebraicTransformOp, no_state{}, handler),
    });
    const continuation = struct {
        /// Increment the resumed transform value for the benchmark lane.
        pub fn apply(value: usize) usize {
            return value + 1;
        }
    };

    const body = struct {
        /// Execute the public algebraic transform micro benchmark body.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(AlgebraicTransformOp, raw_algebraic_transform.current_value, continuation)) {
            return ctx.performProgram(AlgebraicTransformOp, raw_algebraic_transform.current_value, continuation);
        }
    };
};

const raw_algebraic_choice = struct {
    var prompt_ptr: ?*const AlgebraicChoicePrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Return immediately from the raw algebraic choice benchmark.
        pub fn resumeOrReturn() ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).returnNow(current_value + 1);
        }

        /// Preserve the resumed raw algebraic choice answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };

    fn body() ability.ResetError(NoError)!usize {
        _ = try ability.frontend.choice(usize, prompt_ptr.?, handler);
        return 0;
    }
};

const effect_algebraic_choice = struct {
    const no_state = struct {};
    const handler = struct {
        /// Choose the direct-return branch for the public algebraic choice micro benchmark.
        pub fn resumeOrReturn(_: no_state, payload: usize) ability.ResumeOrReturn(usize, usize) {
            return ability.ResumeOrReturn(usize, usize).returnNow(payload + 1);
        }

        /// Preserve the resumed choice answer unchanged.
        pub fn afterResume(_: no_state, answer: usize) usize {
            return answer;
        }
    };
    const program = ability.algebraic.Program(usize, NoError, .{AlgebraicChoiceOp});
    const configured = program.handlers(.{
        ability.algebraic.handleChoice(AlgebraicChoiceOp, no_state{}, handler),
    });
    const continuation = struct {
        /// Return the direct-answer branch if the algebraic choice unexpectedly resumes.
        pub fn apply(_: usize) usize {
            return 0;
        }
    };

    const body = struct {
        /// Execute the public algebraic choice micro benchmark body.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(AlgebraicChoiceOp, raw_algebraic_choice.current_value, continuation)) {
            return ctx.performProgram(AlgebraicChoiceOp, raw_algebraic_choice.current_value, continuation);
        }
    };
};

const raw_algebraic_abort = struct {
    var prompt_ptr: ?*const AlgebraicAbortPrompt = null;
    var current_value: usize = 0;

    const handler = struct {
        /// Convert the raw algebraic abort payload into the enclosing answer.
        pub fn directReturn() usize {
            return current_value + 1;
        }
    };

    fn body() ability.ResetError(NoError)!usize {
        try ability.frontend.abort(prompt_ptr.?, handler);
        return 0;
    }
};

const effect_algebraic_abort = struct {
    const no_state = struct {};
    const handler = struct {
        /// Recover the abort payload unchanged in the public algebraic abort micro benchmark.
        pub fn directReturn(_: no_state, payload: usize) usize {
            return payload;
        }
    };
    const program = ability.algebraic.Program(usize, NoError, .{AlgebraicAbortOp});
    const configured = program.handlers(.{
        ability.algebraic.handleAbort(AlgebraicAbortOp, no_state{}, handler),
    });
    const continuation = struct {
        /// Unreachable continuation placeholder for the abort lane.
        pub fn apply(_: usize) usize {
            unreachable;
        }
    };

    const body = struct {
        /// Execute the public algebraic abort micro benchmark body.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(AlgebraicAbortOp, raw_algebraic_abort.current_value + 1, continuation)) {
            return ctx.performProgram(AlgebraicAbortOp, raw_algebraic_abort.current_value + 1, continuation);
        }
    };
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
    pub fn body(comptime Cap: type, ctx: anytype, comptime items_per_body: usize) ability.ResetError(NoError)!usize {
        var checksum: usize = 0;
        var items_remaining = items_per_body;
        while (items_remaining != 0) : (items_remaining -= 1) {
            checksum += try ability.effect.resource.acquire(Cap, ctx);
        }
        return checksum;
    }
};

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
    /// Execute the append-only writer benchmark body.
    pub fn body(comptime Cap: type, ctx: anytype, comptime items_per_body: usize) ability.ResetError(NoError)!usize {
        var current: usize = 0;
        while (current < items_per_body) : (current += 1) {
            const item = current + 1;
            try ability.effect.writer.tell(Cap, ctx, item);
        }
        return 0;
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

fn runStateRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *RawStatePrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runStateEffectSample(io, runtime, &StateInstance.init(), iterations);
}

fn runStateEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const StateInstance, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        const result = preserveValue(try ability.effect.state.handle(usize, runtime, instance, index, effect_state));
        checksum += result.value + result.state;
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runReaderRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *ReaderPrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runReaderEffectSample(io, runtime, &ReaderInstance.init(), iterations);
}

fn runReaderEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const ReaderInstance, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        checksum += preserveValue(try ability.effect.reader.handle(usize, runtime, instance, index, effect_reader_micro));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runReaderBatchRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *ReaderPrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runReaderBatchEffectSample(io, runtime, &ReaderInstance.init(), iterations);
}

fn runReaderBatchEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const ReaderInstance, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        checksum += preserveValue(try ability.effect.reader.handle(usize, runtime, instance, index, effect_reader_batch));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

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
        checksum += preserveValue(try ability.effect.optional.handle(usize, runtime, instance, effect_optional_return_micro.policy, effect_optional_return_micro));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runOptionalReturnPreludeRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *OptionalReturnPrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runOptionalReturnPreludeEffectSample(io, runtime, &OptionalInstance.init(), iterations);
}

fn runOptionalReturnPreludeEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const OptionalInstance, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_optional_return_prelude.current_value = index;
        checksum += preserveValue(try ability.effect.optional.handle(usize, runtime, instance, effect_optional_return_prelude.policy, effect_optional_return_prelude));
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
        checksum += preserveValue(try ability.effect.optional.handle(usize, runtime, instance, effect_optional_resume_micro.policy, effect_optional_resume_micro));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runOptionalResumeBatchRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *OptionalResumePrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runOptionalResumeBatchEffectSample(io, runtime, &OptionalInstance.init(), iterations);
}

fn runOptionalResumeBatchEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const OptionalInstance, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_optional_resume_batch.current_value = index;
        checksum += preserveValue(try ability.effect.optional.handle(usize, runtime, instance, effect_optional_resume_batch.policy, effect_optional_resume_batch));
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
        checksum += preserveValue(try ability.effect.exception.handle(usize, runtime, instance, effect_exception_micro.catcher, effect_exception_micro));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runExceptionPreludeRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *ExceptionPrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runExceptionPreludeEffectSample(io, runtime, &ExceptionInstance.init(), iterations);
}

fn runExceptionPreludeEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const ExceptionInstance, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_exception_prelude.pending_payload = index;
        checksum += preserveValue(try ability.effect.exception.handle(usize, runtime, instance, effect_exception_prelude.catcher, effect_exception_prelude));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runAlgebraicTransformRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *AlgebraicTransformPrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runAlgebraicTransformEffectSample(io, runtime, iterations);
}

fn runAlgebraicTransformEffectSample(io: std.Io, runtime: *ability.Runtime, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_algebraic_transform.current_value = index;
        checksum += preserveValue(try effect_algebraic_transform.configured.run(runtime, effect_algebraic_transform.body));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runAlgebraicChoiceRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *AlgebraicChoicePrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runAlgebraicChoiceEffectSample(io, runtime, iterations);
}

fn runAlgebraicChoiceEffectSample(io: std.Io, runtime: *ability.Runtime, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_algebraic_choice.current_value = index;
        checksum += preserveValue(try effect_algebraic_choice.configured.run(runtime, effect_algebraic_choice.body));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runAlgebraicAbortRawSample(io: std.Io, runtime: *ability.Runtime, prompt: *AlgebraicAbortPrompt, iterations: usize) !Sample {
    _ = prompt;
    return try runAlgebraicAbortEffectSample(io, runtime, iterations);
}

fn runAlgebraicAbortEffectSample(io: std.Io, runtime: *ability.Runtime, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        raw_algebraic_abort.current_value = index;
        checksum += preserveValue(try effect_algebraic_abort.configured.run(runtime, effect_algebraic_abort.body));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

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
            /// Bridge the resource-effect helper into the benchmark handle body.
            pub fn body(comptime Cap: type, ctx: anytype) ability.ResetError(NoError)!usize {
                return try effect_resource.body(Cap, ctx, items_per_body);
            }
        };
        checksum += preserveValue(try ability.effect.resource.handle(usize, runtime, instance, effect_resource.manager, body));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runWriterRawSample(io: std.Io, allocator: std.mem.Allocator, comptime items_per_body: usize, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        checksum += preserveValue(try raw_writer.body(allocator, items_per_body));
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

fn runWriterEffectSample(io: std.Io, runtime: *ability.Runtime, instance: *const WriterInstance, comptime items_per_body: usize, iterations: usize) !Sample {
    const start = std.Io.Timestamp.now(io, .boot);
    const allocator = std.heap.smp_allocator;
    var checksum: usize = 0;
    var index: usize = 0;
    while (index < iterations) : (index += 1) {
        const body = struct {
            /// Bridge the writer-effect helper into the benchmark handle body.
            pub fn body(comptime Cap: type, ctx: anytype) ability.ResetError(NoError)!usize {
                return try effect_writer.body(Cap, ctx, items_per_body);
            }
        };
        const result = preserveValue(try ability.effect.writer.handle(usize, usize, runtime, instance, allocator, body));
        defer allocator.free(result.items);
        std.mem.doNotOptimizeAway(result.items.ptr);
        var item_checksum: usize = result.items.len + result.value;
        for (result.items) |item| item_checksum += item;
        checksum += item_checksum;
    }
    return .{ .checksum = checksum, .elapsed_ns = elapsedNsSince(io, start) };
}

const LaneReport = struct {
    lane_name: []const u8,
    lane_class: []const u8,
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
        "lane={s} lane_class={s} target_ratio_max={d:.2} raw_checksum={d} effect_checksum={d} raw_sample_ns=[{d},{d},{d},{d},{d}] effect_sample_ns=[{d},{d},{d},{d},{d}] raw_min_ns={d} raw_median_ns={d} raw_max_ns={d} effect_min_ns={d} effect_median_ns={d} effect_max_ns={d}\n",
        .{
            report.lane_name,
            report.lane_class,
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

/// Benchmark every shipped effect family against its chosen comparator lanes.
pub fn main(init: std.process.Init) anyerror!void {
    var state_raw_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer state_raw_runtime.deinit();
    var state_raw_prompt = RawStatePrompt.init();
    raw_state.prompt_ptr = &state_raw_prompt;
    var state_effect_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer state_effect_runtime.deinit();
    var state_effect_instance = StateInstance.init();

    var reader_raw_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer reader_raw_runtime.deinit();
    var reader_raw_prompt = ReaderPrompt.init();
    raw_reader.prompt_ptr = &reader_raw_prompt;
    raw_reader_batch.prompt_ptr = &reader_raw_prompt;
    var reader_effect_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer reader_effect_runtime.deinit();
    var reader_effect_instance = ReaderInstance.init();

    var optional_return_raw_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer optional_return_raw_runtime.deinit();
    var optional_return_prompt = OptionalReturnPrompt.init();
    raw_optional_return.prompt_ptr = &optional_return_prompt;
    raw_optional_return_prelude.prompt_ptr = &optional_return_prompt;
    var optional_return_effect_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer optional_return_effect_runtime.deinit();
    var optional_return_effect_instance = OptionalInstance.init();

    var optional_resume_raw_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer optional_resume_raw_runtime.deinit();
    var optional_resume_prompt = OptionalResumePrompt.init();
    raw_optional_resume.prompt_ptr = &optional_resume_prompt;
    raw_optional_resume_batch.prompt_ptr = &optional_resume_prompt;
    var optional_resume_effect_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer optional_resume_effect_runtime.deinit();
    var optional_resume_effect_instance = OptionalInstance.init();

    var exception_raw_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer exception_raw_runtime.deinit();
    var exception_prompt = ExceptionPrompt.init();
    raw_exception.prompt_ptr = &exception_prompt;
    raw_exception_prelude.prompt_ptr = &exception_prompt;
    var exception_effect_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer exception_effect_runtime.deinit();
    var exception_effect_instance = ExceptionInstance.init();
    var algebraic_transform_raw_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer algebraic_transform_raw_runtime.deinit();
    var algebraic_transform_prompt = AlgebraicTransformPrompt.init();
    raw_algebraic_transform.prompt_ptr = &algebraic_transform_prompt;
    var algebraic_transform_effect_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer algebraic_transform_effect_runtime.deinit();
    var algebraic_choice_raw_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer algebraic_choice_raw_runtime.deinit();
    var algebraic_choice_prompt = AlgebraicChoicePrompt.init();
    raw_algebraic_choice.prompt_ptr = &algebraic_choice_prompt;
    var algebraic_choice_effect_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer algebraic_choice_effect_runtime.deinit();
    var algebraic_abort_raw_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer algebraic_abort_raw_runtime.deinit();
    var algebraic_abort_prompt = AlgebraicAbortPrompt.init();
    raw_algebraic_abort.prompt_ptr = &algebraic_abort_prompt;
    var algebraic_abort_effect_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer algebraic_abort_effect_runtime.deinit();

    var resource_effect_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer resource_effect_runtime.deinit();
    var resource_effect_instance = ResourceInstance.init();

    var writer_effect_runtime = ability.Runtime.init(std.heap.smp_allocator);
    defer writer_effect_runtime.deinit();
    var writer_effect_instance = WriterInstance.init();

    _ = try runStateRawSample(init.io, &state_raw_runtime, &state_raw_prompt, warmup_iterations);
    _ = try runStateEffectSample(init.io, &state_effect_runtime, &state_effect_instance, warmup_iterations);
    _ = try runReaderRawSample(init.io, &reader_raw_runtime, &reader_raw_prompt, warmup_iterations);
    _ = try runReaderEffectSample(init.io, &reader_effect_runtime, &reader_effect_instance, warmup_iterations);
    _ = try runReaderBatchRawSample(init.io, &reader_raw_runtime, &reader_raw_prompt, warmup_iterations);
    _ = try runReaderBatchEffectSample(init.io, &reader_effect_runtime, &reader_effect_instance, warmup_iterations);
    _ = try runOptionalReturnRawSample(init.io, &optional_return_raw_runtime, &optional_return_prompt, warmup_iterations);
    _ = try runOptionalReturnEffectSample(init.io, &optional_return_effect_runtime, &optional_return_effect_instance, warmup_iterations);
    _ = try runOptionalReturnPreludeRawSample(init.io, &optional_return_raw_runtime, &optional_return_prompt, warmup_iterations);
    _ = try runOptionalReturnPreludeEffectSample(init.io, &optional_return_effect_runtime, &optional_return_effect_instance, warmup_iterations);
    _ = try runOptionalResumeRawSample(init.io, &optional_resume_raw_runtime, &optional_resume_prompt, warmup_iterations);
    _ = try runOptionalResumeEffectSample(init.io, &optional_resume_effect_runtime, &optional_resume_effect_instance, warmup_iterations);
    _ = try runOptionalResumeBatchRawSample(init.io, &optional_resume_raw_runtime, &optional_resume_prompt, warmup_iterations);
    _ = try runOptionalResumeBatchEffectSample(init.io, &optional_resume_effect_runtime, &optional_resume_effect_instance, warmup_iterations);
    _ = try runExceptionRawSample(init.io, &exception_raw_runtime, &exception_prompt, warmup_iterations);
    _ = try runExceptionEffectSample(init.io, &exception_effect_runtime, &exception_effect_instance, warmup_iterations);
    _ = try runExceptionPreludeRawSample(init.io, &exception_raw_runtime, &exception_prompt, warmup_iterations);
    _ = try runExceptionPreludeEffectSample(init.io, &exception_effect_runtime, &exception_effect_instance, warmup_iterations);
    _ = try runAlgebraicTransformRawSample(init.io, &algebraic_transform_raw_runtime, &algebraic_transform_prompt, warmup_iterations);
    _ = try runAlgebraicTransformEffectSample(init.io, &algebraic_transform_effect_runtime, warmup_iterations);
    _ = try runAlgebraicChoiceRawSample(init.io, &algebraic_choice_raw_runtime, &algebraic_choice_prompt, warmup_iterations);
    _ = try runAlgebraicChoiceEffectSample(init.io, &algebraic_choice_effect_runtime, warmup_iterations);
    _ = try runAlgebraicAbortRawSample(init.io, &algebraic_abort_raw_runtime, &algebraic_abort_prompt, warmup_iterations);
    _ = try runAlgebraicAbortEffectSample(init.io, &algebraic_abort_effect_runtime, warmup_iterations);
    _ = try runResourceRawSample(init.io, std.heap.smp_allocator, resource_small_items_per_body, warmup_iterations);
    _ = try runResourceEffectSample(init.io, &resource_effect_runtime, &resource_effect_instance, resource_small_items_per_body, warmup_iterations);
    _ = try runResourceRawSample(init.io, std.heap.smp_allocator, resource_large_items_per_body, warmup_iterations);
    _ = try runResourceEffectSample(init.io, &resource_effect_runtime, &resource_effect_instance, resource_large_items_per_body, warmup_iterations);
    _ = try runWriterRawSample(init.io, std.heap.smp_allocator, 1, warmup_iterations);
    _ = try runWriterEffectSample(init.io, &writer_effect_runtime, &writer_effect_instance, 1, warmup_iterations);
    _ = try runWriterRawSample(init.io, std.heap.smp_allocator, writer_small_items_per_body, warmup_iterations);
    _ = try runWriterEffectSample(init.io, &writer_effect_runtime, &writer_effect_instance, writer_small_items_per_body, warmup_iterations);
    _ = try runWriterRawSample(init.io, std.heap.smp_allocator, writer_large_items_per_body, warmup_iterations);
    _ = try runWriterEffectSample(init.io, &writer_effect_runtime, &writer_effect_instance, writer_large_items_per_body, warmup_iterations);

    var state_raw_samples = [_]u64{0} ** samples_per_run;
    var state_effect_samples = [_]u64{0} ** samples_per_run;
    var reader_raw_samples = [_]u64{0} ** samples_per_run;
    var reader_effect_samples = [_]u64{0} ** samples_per_run;
    var reader_batch_raw_samples = [_]u64{0} ** samples_per_run;
    var reader_batch_effect_samples = [_]u64{0} ** samples_per_run;
    var optional_return_raw_samples = [_]u64{0} ** samples_per_run;
    var optional_return_effect_samples = [_]u64{0} ** samples_per_run;
    var opt_ret_pre_raw_samples = [_]u64{0} ** samples_per_run;
    var opt_ret_pre_eff_samples = [_]u64{0} ** samples_per_run;
    var optional_resume_raw_samples = [_]u64{0} ** samples_per_run;
    var optional_resume_effect_samples = [_]u64{0} ** samples_per_run;
    var opt_res_batch_raw_samples = [_]u64{0} ** samples_per_run;
    var opt_res_batch_eff_samples = [_]u64{0} ** samples_per_run;
    var exception_raw_samples = [_]u64{0} ** samples_per_run;
    var exception_effect_samples = [_]u64{0} ** samples_per_run;
    var exception_prelude_raw_samples = [_]u64{0} ** samples_per_run;
    var exn_pre_eff_samples = [_]u64{0} ** samples_per_run;
    var alg_transform_raw_samples = [_]u64{0} ** samples_per_run;
    var alg_transform_effect_samples = [_]u64{0} ** samples_per_run;
    var alg_choice_raw_samples = [_]u64{0} ** samples_per_run;
    var alg_choice_effect_samples = [_]u64{0} ** samples_per_run;
    var alg_abort_raw_samples = [_]u64{0} ** samples_per_run;
    var alg_abort_effect_samples = [_]u64{0} ** samples_per_run;
    var resource4_raw_samples = [_]u64{0} ** samples_per_run;
    var resource4_effect_samples = [_]u64{0} ** samples_per_run;
    var resource32_raw_samples = [_]u64{0} ** samples_per_run;
    var resource32_effect_samples = [_]u64{0} ** samples_per_run;
    var writer_micro_raw_samples = [_]u64{0} ** samples_per_run;
    var writer_micro_effect_samples = [_]u64{0} ** samples_per_run;
    var writer16_raw_samples = [_]u64{0} ** samples_per_run;
    var writer16_effect_samples = [_]u64{0} ** samples_per_run;
    var writer64_raw_samples = [_]u64{0} ** samples_per_run;
    var writer64_effect_samples = [_]u64{0} ** samples_per_run;

    var state_raw_checksum: ?usize = null;
    var state_effect_checksum: ?usize = null;
    var reader_raw_checksum: ?usize = null;
    var reader_effect_checksum: ?usize = null;
    var reader_batch_raw_checksum: ?usize = null;
    var reader_batch_effect_checksum: ?usize = null;
    var opt_return_raw_checksum: ?usize = null;
    var opt_return_effect_checksum: ?usize = null;
    var opt_ret_pre_raw_cksum: ?usize = null;
    var opt_ret_pre_eff_cksum: ?usize = null;
    var opt_resume_raw_checksum: ?usize = null;
    var opt_resume_effect_checksum: ?usize = null;
    var opt_resume_batch_raw_checksum: ?usize = null;
    var opt_res_batch_eff_cksum: ?usize = null;
    var exception_raw_checksum: ?usize = null;
    var exception_effect_checksum: ?usize = null;
    var exception_prelude_raw_checksum: ?usize = null;
    var exn_pre_eff_cksum: ?usize = null;
    var alg_transform_raw_cksum: ?usize = null;
    var alg_transform_effect_cksum: ?usize = null;
    var alg_choice_raw_cksum: ?usize = null;
    var alg_choice_effect_cksum: ?usize = null;
    var alg_abort_raw_cksum: ?usize = null;
    var alg_abort_effect_cksum: ?usize = null;
    var resource4_raw_checksum: ?usize = null;
    var resource4_effect_checksum: ?usize = null;
    var resource32_raw_checksum: ?usize = null;
    var resource32_effect_checksum: ?usize = null;
    var writer_micro_raw_checksum: ?usize = null;
    var writer_micro_effect_checksum: ?usize = null;
    var writer16_raw_checksum: ?usize = null;
    var writer16_effect_checksum: ?usize = null;
    var writer64_raw_checksum: ?usize = null;
    var writer64_effect_checksum: ?usize = null;

    var index: usize = 0;
    while (index < samples_per_run) : (index += 1) {
        const state_raw_sample = try runStateRawSample(init.io, &state_raw_runtime, &state_raw_prompt, timed_iterations);
        const state_effect_sample = try runStateEffectSample(init.io, &state_effect_runtime, &state_effect_instance, timed_iterations);
        const reader_raw_sample = try runReaderRawSample(init.io, &reader_raw_runtime, &reader_raw_prompt, timed_iterations);
        const reader_effect_sample = try runReaderEffectSample(init.io, &reader_effect_runtime, &reader_effect_instance, timed_iterations);
        const reader_batch_raw_sample = try runReaderBatchRawSample(init.io, &reader_raw_runtime, &reader_raw_prompt, timed_iterations);
        const reader_batch_effect_sample = try runReaderBatchEffectSample(init.io, &reader_effect_runtime, &reader_effect_instance, timed_iterations);
        const optional_return_raw_sample = try runOptionalReturnRawSample(init.io, &optional_return_raw_runtime, &optional_return_prompt, timed_iterations);
        const optional_return_effect_sample = try runOptionalReturnEffectSample(init.io, &optional_return_effect_runtime, &optional_return_effect_instance, timed_iterations);
        const opt_ret_pre_raw_sample = try runOptionalReturnPreludeRawSample(init.io, &optional_return_raw_runtime, &optional_return_prompt, timed_iterations);
        const opt_ret_pre_eff_sample = try runOptionalReturnPreludeEffectSample(init.io, &optional_return_effect_runtime, &optional_return_effect_instance, timed_iterations);
        const optional_resume_raw_sample = try runOptionalResumeRawSample(init.io, &optional_resume_raw_runtime, &optional_resume_prompt, timed_iterations);
        const optional_resume_effect_sample = try runOptionalResumeEffectSample(init.io, &optional_resume_effect_runtime, &optional_resume_effect_instance, timed_iterations);
        const opt_res_batch_raw_sample = try runOptionalResumeBatchRawSample(init.io, &optional_resume_raw_runtime, &optional_resume_prompt, timed_iterations);
        const opt_res_batch_eff_sample = try runOptionalResumeBatchEffectSample(init.io, &optional_resume_effect_runtime, &optional_resume_effect_instance, timed_iterations);
        const exception_raw_sample = try runExceptionRawSample(init.io, &exception_raw_runtime, &exception_prompt, timed_iterations);
        const exception_effect_sample = try runExceptionEffectSample(init.io, &exception_effect_runtime, &exception_effect_instance, timed_iterations);
        const exception_prelude_raw_sample = try runExceptionPreludeRawSample(init.io, &exception_raw_runtime, &exception_prompt, timed_iterations);
        const exn_pre_eff_sample = try runExceptionPreludeEffectSample(init.io, &exception_effect_runtime, &exception_effect_instance, timed_iterations);
        const algebraic_transform_raw_sample = try runAlgebraicTransformRawSample(init.io, &algebraic_transform_raw_runtime, &algebraic_transform_prompt, timed_iterations);
        const alg_transform_effect_sample = try runAlgebraicTransformEffectSample(init.io, &algebraic_transform_effect_runtime, timed_iterations);
        const algebraic_choice_raw_sample = try runAlgebraicChoiceRawSample(init.io, &algebraic_choice_raw_runtime, &algebraic_choice_prompt, timed_iterations);
        const alg_choice_effect_sample = try runAlgebraicChoiceEffectSample(init.io, &algebraic_choice_effect_runtime, timed_iterations);
        const algebraic_abort_raw_sample = try runAlgebraicAbortRawSample(init.io, &algebraic_abort_raw_runtime, &algebraic_abort_prompt, timed_iterations);
        const alg_abort_effect_sample = try runAlgebraicAbortEffectSample(init.io, &algebraic_abort_effect_runtime, timed_iterations);
        const resource4_raw_sample = try runResourceRawSample(init.io, std.heap.smp_allocator, resource_small_items_per_body, timed_iterations);
        const resource4_effect_sample = try runResourceEffectSample(init.io, &resource_effect_runtime, &resource_effect_instance, resource_small_items_per_body, timed_iterations);
        const resource32_raw_sample = try runResourceRawSample(init.io, std.heap.smp_allocator, resource_large_items_per_body, timed_iterations);
        const resource32_effect_sample = try runResourceEffectSample(init.io, &resource_effect_runtime, &resource_effect_instance, resource_large_items_per_body, timed_iterations);
        const writer_micro_raw_sample = try runWriterRawSample(init.io, std.heap.smp_allocator, 1, timed_iterations);
        const writer_micro_effect_sample = try runWriterEffectSample(init.io, &writer_effect_runtime, &writer_effect_instance, 1, timed_iterations);
        const writer16_raw_sample = try runWriterRawSample(init.io, std.heap.smp_allocator, writer_small_items_per_body, timed_iterations);
        const writer16_effect_sample = try runWriterEffectSample(init.io, &writer_effect_runtime, &writer_effect_instance, writer_small_items_per_body, timed_iterations);
        const writer64_raw_sample = try runWriterRawSample(init.io, std.heap.smp_allocator, writer_large_items_per_body, timed_iterations);
        const writer64_effect_sample = try runWriterEffectSample(init.io, &writer_effect_runtime, &writer_effect_instance, writer_large_items_per_body, timed_iterations);

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

        if (reader_batch_raw_checksum) |checksum| {
            if (checksum != reader_batch_raw_sample.checksum) return error.ReaderBatchRawChecksumMismatch;
        } else reader_batch_raw_checksum = reader_batch_raw_sample.checksum;
        if (reader_batch_effect_checksum) |checksum| {
            if (checksum != reader_batch_effect_sample.checksum) return error.ReaderBatchEffectChecksumMismatch;
        } else reader_batch_effect_checksum = reader_batch_effect_sample.checksum;

        if (opt_return_raw_checksum) |checksum| {
            if (checksum != optional_return_raw_sample.checksum) return error.OptionalReturnRawChecksumMismatch;
        } else opt_return_raw_checksum = optional_return_raw_sample.checksum;
        if (opt_return_effect_checksum) |checksum| {
            if (checksum != optional_return_effect_sample.checksum) return error.OptionalReturnEffectChecksumMismatch;
        } else opt_return_effect_checksum = optional_return_effect_sample.checksum;

        if (opt_ret_pre_raw_cksum) |checksum| {
            if (checksum != opt_ret_pre_raw_sample.checksum) return error.OptionalReturnPreludeRawChecksumMismatch;
        } else opt_ret_pre_raw_cksum = opt_ret_pre_raw_sample.checksum;
        if (opt_ret_pre_eff_cksum) |checksum| {
            if (checksum != opt_ret_pre_eff_sample.checksum) return error.OptionalReturnPreludeEffectChecksumMismatch;
        } else opt_ret_pre_eff_cksum = opt_ret_pre_eff_sample.checksum;

        if (opt_resume_raw_checksum) |checksum| {
            if (checksum != optional_resume_raw_sample.checksum) return error.OptionalResumeRawChecksumMismatch;
        } else opt_resume_raw_checksum = optional_resume_raw_sample.checksum;
        if (opt_resume_effect_checksum) |checksum| {
            if (checksum != optional_resume_effect_sample.checksum) return error.OptionalResumeEffectChecksumMismatch;
        } else opt_resume_effect_checksum = optional_resume_effect_sample.checksum;

        if (opt_resume_batch_raw_checksum) |checksum| {
            if (checksum != opt_res_batch_raw_sample.checksum) return error.OptionalResumeBatchRawChecksumMismatch;
        } else opt_resume_batch_raw_checksum = opt_res_batch_raw_sample.checksum;
        if (opt_res_batch_eff_cksum) |checksum| {
            if (checksum != opt_res_batch_eff_sample.checksum) return error.OptionalResumeBatchEffectChecksumMismatch;
        } else opt_res_batch_eff_cksum = opt_res_batch_eff_sample.checksum;

        if (exception_raw_checksum) |checksum| {
            if (checksum != exception_raw_sample.checksum) return error.ExceptionRawChecksumMismatch;
        } else exception_raw_checksum = exception_raw_sample.checksum;
        if (exception_effect_checksum) |checksum| {
            if (checksum != exception_effect_sample.checksum) return error.ExceptionEffectChecksumMismatch;
        } else exception_effect_checksum = exception_effect_sample.checksum;

        if (exception_prelude_raw_checksum) |checksum| {
            if (checksum != exception_prelude_raw_sample.checksum) return error.ExceptionPreludeRawChecksumMismatch;
        } else exception_prelude_raw_checksum = exception_prelude_raw_sample.checksum;
        if (exn_pre_eff_cksum) |checksum| {
            if (checksum != exn_pre_eff_sample.checksum) return error.ExceptionPreludeEffectChecksumMismatch;
        } else exn_pre_eff_cksum = exn_pre_eff_sample.checksum;

        if (alg_transform_raw_cksum) |checksum| {
            if (checksum != algebraic_transform_raw_sample.checksum) return error.AlgebraicTransformRawChecksumMismatch;
        } else alg_transform_raw_cksum = algebraic_transform_raw_sample.checksum;
        if (alg_transform_effect_cksum) |checksum| {
            if (checksum != alg_transform_effect_sample.checksum) return error.AlgebraicTransformEffectChecksumMismatch;
        } else alg_transform_effect_cksum = alg_transform_effect_sample.checksum;

        if (alg_choice_raw_cksum) |checksum| {
            if (checksum != algebraic_choice_raw_sample.checksum) return error.AlgebraicChoiceRawChecksumMismatch;
        } else alg_choice_raw_cksum = algebraic_choice_raw_sample.checksum;
        if (alg_choice_effect_cksum) |checksum| {
            if (checksum != alg_choice_effect_sample.checksum) return error.AlgebraicChoiceEffectChecksumMismatch;
        } else alg_choice_effect_cksum = alg_choice_effect_sample.checksum;

        if (alg_abort_raw_cksum) |checksum| {
            if (checksum != algebraic_abort_raw_sample.checksum) return error.AlgebraicAbortRawChecksumMismatch;
        } else alg_abort_raw_cksum = algebraic_abort_raw_sample.checksum;
        if (alg_abort_effect_cksum) |checksum| {
            if (checksum != alg_abort_effect_sample.checksum) return error.AlgebraicAbortEffectChecksumMismatch;
        } else alg_abort_effect_cksum = alg_abort_effect_sample.checksum;

        if (resource4_raw_checksum) |checksum| {
            if (checksum != resource4_raw_sample.checksum) return error.Resource4RawChecksumMismatch;
        } else resource4_raw_checksum = resource4_raw_sample.checksum;
        if (resource4_effect_checksum) |checksum| {
            if (checksum != resource4_effect_sample.checksum) return error.Resource4EffectChecksumMismatch;
        } else resource4_effect_checksum = resource4_effect_sample.checksum;

        if (resource32_raw_checksum) |checksum| {
            if (checksum != resource32_raw_sample.checksum) return error.Resource32RawChecksumMismatch;
        } else resource32_raw_checksum = resource32_raw_sample.checksum;
        if (resource32_effect_checksum) |checksum| {
            if (checksum != resource32_effect_sample.checksum) return error.Resource32EffectChecksumMismatch;
        } else resource32_effect_checksum = resource32_effect_sample.checksum;

        if (writer_micro_raw_checksum) |checksum| {
            if (checksum != writer_micro_raw_sample.checksum) return error.WriterMicroRawChecksumMismatch;
        } else writer_micro_raw_checksum = writer_micro_raw_sample.checksum;
        if (writer_micro_effect_checksum) |checksum| {
            if (checksum != writer_micro_effect_sample.checksum) return error.WriterMicroEffectChecksumMismatch;
        } else writer_micro_effect_checksum = writer_micro_effect_sample.checksum;

        if (writer16_raw_checksum) |checksum| {
            if (checksum != writer16_raw_sample.checksum) return error.Writer16RawChecksumMismatch;
        } else writer16_raw_checksum = writer16_raw_sample.checksum;
        if (writer16_effect_checksum) |checksum| {
            if (checksum != writer16_effect_sample.checksum) return error.Writer16EffectChecksumMismatch;
        } else writer16_effect_checksum = writer16_effect_sample.checksum;

        if (writer64_raw_checksum) |checksum| {
            if (checksum != writer64_raw_sample.checksum) return error.Writer64RawChecksumMismatch;
        } else writer64_raw_checksum = writer64_raw_sample.checksum;
        if (writer64_effect_checksum) |checksum| {
            if (checksum != writer64_effect_sample.checksum) return error.Writer64EffectChecksumMismatch;
        } else writer64_effect_checksum = writer64_effect_sample.checksum;

        state_raw_samples[index] = state_raw_sample.elapsed_ns;
        state_effect_samples[index] = state_effect_sample.elapsed_ns;
        reader_raw_samples[index] = reader_raw_sample.elapsed_ns;
        reader_effect_samples[index] = reader_effect_sample.elapsed_ns;
        reader_batch_raw_samples[index] = reader_batch_raw_sample.elapsed_ns;
        reader_batch_effect_samples[index] = reader_batch_effect_sample.elapsed_ns;
        optional_return_raw_samples[index] = optional_return_raw_sample.elapsed_ns;
        optional_return_effect_samples[index] = optional_return_effect_sample.elapsed_ns;
        opt_ret_pre_raw_samples[index] = opt_ret_pre_raw_sample.elapsed_ns;
        opt_ret_pre_eff_samples[index] = opt_ret_pre_eff_sample.elapsed_ns;
        optional_resume_raw_samples[index] = optional_resume_raw_sample.elapsed_ns;
        optional_resume_effect_samples[index] = optional_resume_effect_sample.elapsed_ns;
        opt_res_batch_raw_samples[index] = opt_res_batch_raw_sample.elapsed_ns;
        opt_res_batch_eff_samples[index] = opt_res_batch_eff_sample.elapsed_ns;
        exception_raw_samples[index] = exception_raw_sample.elapsed_ns;
        exception_effect_samples[index] = exception_effect_sample.elapsed_ns;
        exception_prelude_raw_samples[index] = exception_prelude_raw_sample.elapsed_ns;
        exn_pre_eff_samples[index] = exn_pre_eff_sample.elapsed_ns;
        alg_transform_raw_samples[index] = algebraic_transform_raw_sample.elapsed_ns;
        alg_transform_effect_samples[index] = alg_transform_effect_sample.elapsed_ns;
        alg_choice_raw_samples[index] = algebraic_choice_raw_sample.elapsed_ns;
        alg_choice_effect_samples[index] = alg_choice_effect_sample.elapsed_ns;
        alg_abort_raw_samples[index] = algebraic_abort_raw_sample.elapsed_ns;
        alg_abort_effect_samples[index] = alg_abort_effect_sample.elapsed_ns;
        resource4_raw_samples[index] = resource4_raw_sample.elapsed_ns;
        resource4_effect_samples[index] = resource4_effect_sample.elapsed_ns;
        resource32_raw_samples[index] = resource32_raw_sample.elapsed_ns;
        resource32_effect_samples[index] = resource32_effect_sample.elapsed_ns;
        writer_micro_raw_samples[index] = writer_micro_raw_sample.elapsed_ns;
        writer_micro_effect_samples[index] = writer_micro_effect_sample.elapsed_ns;
        writer16_raw_samples[index] = writer16_raw_sample.elapsed_ns;
        writer16_effect_samples[index] = writer16_effect_sample.elapsed_ns;
        writer64_raw_samples[index] = writer64_raw_sample.elapsed_ns;
        writer64_effect_samples[index] = writer64_effect_sample.elapsed_ns;
    }

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "timed_iterations={d} warmup_iterations={d} samples_per_run={d} lanes=17 schema_version=2\n",
        .{ timed_iterations, warmup_iterations, samples_per_run },
    );
    try printLane(stdout, .{ .lane_name = "state_micro", .lane_class = "micro", .target_ratio_max = state_micro_target_ratio_max, .raw_samples = &state_raw_samples, .effect_samples = &state_effect_samples, .raw_checksum = state_raw_checksum.?, .effect_checksum = state_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "reader_micro", .lane_class = "micro", .target_ratio_max = reader_micro_target_ratio_max, .raw_samples = &reader_raw_samples, .effect_samples = &reader_effect_samples, .raw_checksum = reader_raw_checksum.?, .effect_checksum = reader_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "reader_batch8", .lane_class = "amortized", .target_ratio_max = reader_batch_target_ratio_max, .raw_samples = &reader_batch_raw_samples, .effect_samples = &reader_batch_effect_samples, .raw_checksum = reader_batch_raw_checksum.?, .effect_checksum = reader_batch_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "optional_return_now_micro", .lane_class = "micro", .target_ratio_max = opt_ret_micro_ratio_max, .raw_samples = &optional_return_raw_samples, .effect_samples = &optional_return_effect_samples, .raw_checksum = opt_return_raw_checksum.?, .effect_checksum = opt_return_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "optional_return_now_prelude8", .lane_class = "amortized", .target_ratio_max = opt_ret_pre_ratio_max, .raw_samples = &opt_ret_pre_raw_samples, .effect_samples = &opt_ret_pre_eff_samples, .raw_checksum = opt_ret_pre_raw_cksum.?, .effect_checksum = opt_ret_pre_eff_cksum.? });
    try printLane(stdout, .{ .lane_name = "optional_resume_with_micro", .lane_class = "micro", .target_ratio_max = opt_res_micro_ratio_max, .raw_samples = &optional_resume_raw_samples, .effect_samples = &optional_resume_effect_samples, .raw_checksum = opt_resume_raw_checksum.?, .effect_checksum = opt_resume_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "optional_resume_with_batch8", .lane_class = "amortized", .target_ratio_max = opt_res_batch_ratio_max, .raw_samples = &opt_res_batch_raw_samples, .effect_samples = &opt_res_batch_eff_samples, .raw_checksum = opt_resume_batch_raw_checksum.?, .effect_checksum = opt_res_batch_eff_cksum.? });
    try printLane(stdout, .{ .lane_name = "exception_throw_micro", .lane_class = "micro", .target_ratio_max = exn_micro_ratio_max, .raw_samples = &exception_raw_samples, .effect_samples = &exception_effect_samples, .raw_checksum = exception_raw_checksum.?, .effect_checksum = exception_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "exception_throw_prelude8", .lane_class = "amortized", .target_ratio_max = exn_pre_ratio_max, .raw_samples = &exception_prelude_raw_samples, .effect_samples = &exn_pre_eff_samples, .raw_checksum = exception_prelude_raw_checksum.?, .effect_checksum = exn_pre_eff_cksum.? });
    try printLane(stdout, .{ .lane_name = "algebraic_transform_micro", .lane_class = "micro", .target_ratio_max = alg_transform_micro_max, .raw_samples = &alg_transform_raw_samples, .effect_samples = &alg_transform_effect_samples, .raw_checksum = alg_transform_raw_cksum.?, .effect_checksum = alg_transform_effect_cksum.? });
    try printLane(stdout, .{ .lane_name = "algebraic_choice_return_now_micro", .lane_class = "micro", .target_ratio_max = alg_choice_micro_max, .raw_samples = &alg_choice_raw_samples, .effect_samples = &alg_choice_effect_samples, .raw_checksum = alg_choice_raw_cksum.?, .effect_checksum = alg_choice_effect_cksum.? });
    try printLane(stdout, .{ .lane_name = "algebraic_abort_micro", .lane_class = "investigation", .target_ratio_max = alg_abort_micro_max, .raw_samples = &alg_abort_raw_samples, .effect_samples = &alg_abort_effect_samples, .raw_checksum = alg_abort_raw_cksum.?, .effect_checksum = alg_abort_effect_cksum.? });
    try printLane(stdout, .{ .lane_name = "resource_normal_4", .lane_class = "investigation", .target_ratio_max = resource4_target_ratio_max, .raw_samples = &resource4_raw_samples, .effect_samples = &resource4_effect_samples, .raw_checksum = resource4_raw_checksum.?, .effect_checksum = resource4_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "resource_normal_32", .lane_class = "investigation", .target_ratio_max = resource32_target_ratio_max, .raw_samples = &resource32_raw_samples, .effect_samples = &resource32_effect_samples, .raw_checksum = resource32_raw_checksum.?, .effect_checksum = resource32_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "writer_micro", .lane_class = "micro", .target_ratio_max = writer_micro_target_ratio_max, .raw_samples = &writer_micro_raw_samples, .effect_samples = &writer_micro_effect_samples, .raw_checksum = writer_micro_raw_checksum.?, .effect_checksum = writer_micro_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "writer_batch16", .lane_class = "investigation", .target_ratio_max = writer16_target_ratio_max, .raw_samples = &writer16_raw_samples, .effect_samples = &writer16_effect_samples, .raw_checksum = writer16_raw_checksum.?, .effect_checksum = writer16_effect_checksum.? });
    try printLane(stdout, .{ .lane_name = "writer_batch64", .lane_class = "investigation", .target_ratio_max = writer64_target_ratio_max, .raw_samples = &writer64_raw_samples, .effect_samples = &writer64_effect_samples, .raw_checksum = writer64_raw_checksum.?, .effect_checksum = writer64_effect_checksum.? });
    try stdout.flush();
}
