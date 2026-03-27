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
