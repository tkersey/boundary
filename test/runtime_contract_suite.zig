const prompt_support = @import("prompt_support");
const runtime_contracts = @import("runtime_contract_registry");
const shift = @import("shift");
const std = @import("std");
const survey_resume_transform_executes = @import("survey_resume_transform_executes");

test "runtime contract registry stays in sync with the executable suite" {
    try std.testing.expectEqual(@as(usize, 6), runtime_contracts.cases.len);
}

test "missing prompt still fails closed through the public API" {
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, i32, i32, NoError);
    var prompt = DemoPrompt.init();

    const handle = struct {
        /// Supply the resumed value for the runtime-contract survey case.
        pub fn resumeValue() i32 {
            return 1;
        }
        /// Preserve the resumed value on the enclosing answer path.
        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };

    try std.testing.expectError(error.MissingPrompt, prompt_support.perform(i32, &prompt, handle));
}

test "cross-thread runtime misuse still fails closed" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Result = struct {
        err: ?shift.RuntimeError = null,
    };
    var result = Result{};

    const worker = struct {
        fn run(runtime_ptr: *shift.Runtime, result_ptr: *Result) void {
            runtime_ptr.deinitChecked() catch |err| {
                result_ptr.err = err;
                return;
            };
        }
    }.run;

    const thread = try std.Thread.spawn(.{}, worker, .{ &runtime, &result });
    thread.join();
    try std.testing.expectEqual(error.CrossThread, result.err.?);
}

test "runtime deinit rejects active reset" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, usize, usize, NoError);
    var prompt = DemoPrompt.init();

    const handler = struct {
        /// Supply a placeholder resume value so the runtime stays active while the continuation runs.
        pub fn resumeValue() usize {
            return 0;
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };
    const continuation = struct {
        var runtime_ptr: *shift.Runtime = undefined;

        /// Probe the runtime-busy contract from the resumed continuation.
        pub fn apply(_: usize) anyerror!usize {
            runtime_ptr.deinitChecked() catch |err| {
                if (err != error.RuntimeBusy) unreachable;
                return 7;
            };
            unreachable;
        }
    };

    continuation.runtime_ptr = &runtime;
    const answer = try prompt_support.run(&runtime, &prompt, prompt_support.transformProgram(DemoPrompt, usize, handler, continuation));
    try std.testing.expectEqual(@as(usize, 7), answer);
}

test "independent runtimes can execute on the same thread while another runtime is active" {
    var outer_runtime = shift.Runtime.init(std.testing.allocator);
    defer outer_runtime.deinit();
    var inner_runtime = shift.Runtime.init(std.testing.allocator);
    defer inner_runtime.deinit();

    const NoError = error{};
    const OuterPrompt = prompt_support.Prompt(.resume_then_transform, usize, usize, NoError);
    const InnerPrompt = prompt_support.Prompt(.resume_then_transform, usize, usize, NoError);
    var outer_prompt = OuterPrompt.init();
    var inner_prompt = InnerPrompt.init();

    const outer_handler = struct {
        /// Keep the outer runtime active while the nested runtime runs.
        pub fn resumeValue() usize {
            return 1;
        }

        /// Return the nested runtime answer unchanged.
        pub fn afterResume(value: usize) usize {
            return value;
        }
    };
    const inner_handler = struct {
        /// Provide the nested runtime resume payload.
        pub fn resumeValue() usize {
            return 2;
        }

        /// Add one observable transform step inside the nested runtime.
        pub fn afterResume(value: usize) usize {
            return value + 5;
        }
    };
    const inner_continuation = struct {
        /// Complete the nested continuation so the outer runtime can observe success.
        pub fn apply(value: usize) anyerror!usize {
            return value + 10;
        }
    };
    const outer_continuation = struct {
        var inner_runtime_ptr: *shift.Runtime = undefined;
        var inner_prompt_ptr: *InnerPrompt = undefined;

        /// Run the nested prompt on the second runtime while the outer runtime stays active.
        pub fn apply(_: usize) anyerror!usize {
            return try prompt_support.run(
                inner_runtime_ptr,
                inner_prompt_ptr,
                prompt_support.transformProgram(InnerPrompt, usize, inner_handler, inner_continuation),
            );
        }
    };

    outer_continuation.inner_runtime_ptr = &inner_runtime;
    outer_continuation.inner_prompt_ptr = &inner_prompt;
    const answer = try prompt_support.run(
        &outer_runtime,
        &outer_prompt,
        prompt_support.transformProgram(OuterPrompt, usize, outer_handler, outer_continuation),
    );
    try std.testing.expectEqual(@as(usize, 17), answer);
}

test "destroyed runtime rejects later reset use" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    try runtime.deinitChecked();
    try std.testing.expectError(error.RuntimeDestroyed, runtime.deinitChecked());

    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, usize, usize, NoError);
    var prompt = DemoPrompt.init();

    try std.testing.expectError(error.RuntimeDestroyed, prompt_support.run(&runtime, &prompt, prompt_support.pureProgram(DemoPrompt, 7)));
}

test "unsupported non-diagonal completion still fails closed" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, i32, []const u8, NoError);
    var prompt = DemoPrompt.init();

    try std.testing.expectError(error.NonDiagonalComplete, prompt_support.run(&runtime, &prompt, prompt_support.pureProgram(DemoPrompt, 7)));
}

test "runtime-positive one-shot survey fixture still executes" {
    try survey_resume_transform_executes.main();
}
