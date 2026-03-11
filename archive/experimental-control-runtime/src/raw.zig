const kernel = @import("raw_kernel.zig");
const std = @import("std");
const surface = @import("raw_surface.zig");

/// Runtime errors surfaced by the fiber-backed control core.
pub const Error = kernel.Error;
/// Setup failures that can occur before user code enters `reset`.
pub const SetupError = kernel.SetupError;
/// Thread-affine runtime that owns stackful continuations.
pub const Runtime = kernel.Runtime;
/// Region guard that forbids `shift` while unsafe work is active.
pub const NoShiftGuard = kernel.NoShiftGuard;

/// Typed prompt handle with per-instance identity.
pub fn Prompt(
    comptime RequestType: type,
    comptime ResumeType: type,
    comptime AnswerType: type,
    comptime ErrorSetType: type,
) type {
    return struct {
        marker: u8 = 0,
        owner_cookie: usize = 0,

        /// Request payload yielded from `shift`.
        pub const Request = RequestType;
        /// Resume payload accepted when the pending edge is resolved.
        pub const Resume = ResumeType;
        /// Final answer type produced by `reset`.
        pub const Answer = AnswerType;
        /// User-visible error surface for the prompt body.
        pub const ErrorSet = ErrorSetType;

        /// Initialize a fresh prompt handle instance.
        pub fn init() @This() {
            return .{};
        }
    };
}

/// Runtime-visible error union for user-provided errors.
pub fn ControlError(comptime ErrorSet: type) type {
    return kernel.ControlError(ErrorSet);
}

/// Full `reset`-path error union including setup failures.
pub fn ResetError(comptime ErrorSet: type) type {
    return kernel.ResetError(ErrorSet);
}

/// Result of driving a delimiter until completion, pending ownership, or cancellation.
pub fn Outcome(comptime Spec: type) type {
    return surface.Outcome(Spec);
}

/// Explicit escaped owner for one-shot delayed resolution.
pub fn EscapedOwner(comptime Spec: type) type {
    return surface.EscapedOwner(Spec);
}

/// Primary one-shot pending owner used by the direct-style loop.
pub fn Pending(comptime Spec: type) type {
    return surface.Pending(Spec);
}

/// Run `body` under a fresh delimiter owned by `prompt`.
pub fn reset(
    runtime: *Runtime,
    prompt: anytype,
    body: *const fn () ResetError(@TypeOf(prompt.*).ErrorSet)!@TypeOf(prompt.*).Answer,
) ResetError(@TypeOf(prompt.*).ErrorSet)!Outcome(@TypeOf(prompt.*)) {
    const Spec = @TypeOf(prompt.*);
    return surface.reset(Spec, runtime, prompt, body);
}

/// Capture the nearest active delimiter owned by `prompt`.
pub fn shift(
    prompt: anytype,
    request: @TypeOf(prompt.*).Request,
) ControlError(@TypeOf(prompt.*).ErrorSet)!@TypeOf(prompt.*).Resume {
    const Spec = @TypeOf(prompt.*);
    return surface.shift(Spec, prompt, request);
}

test {
    _ = Error;
    _ = SetupError;
    _ = Runtime;
    _ = NoShiftGuard;
    _ = Prompt;
}

test "no-shift guard rejects capture" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = void;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        var runtime_ptr: *Runtime = undefined;

        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            var guard: NoShiftGuard = .{};
            try guard.enter(runtime_ptr);
            defer guard.leave();
            _ = try shift(demo_spec, {});
            return 1;
        }
    };

    demo.runtime_ptr = &runtime;
    try std.testing.expectError(error.ShiftForbidden, reset(demo_spec, &runtime, demo.body));
}

test "no-shift guard checked leave rejects cross-thread use" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    var guard: NoShiftGuard = .{};
    try guard.enter(&runtime);
    var attempt = struct {
        guard: NoShiftGuard,
        result: ?Error = null,

        fn run(self: *@This()) void {
            self.guard.leaveChecked() catch |err| {
                self.result = err;
                return;
            };
        }
    }{
        .guard = guard,
    };

    var thread = try std.Thread.spawn(.{}, @TypeOf(attempt).run, .{&attempt});
    thread.join();
    try std.testing.expectEqual(error.CrossThread, attempt.result.?);
    try guard.leaveChecked();
}

test "no-shift guard copied alias cannot release owner depth" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    var guard: NoShiftGuard = .{};
    try guard.enter(&runtime);
    var alias = guard;

    try std.testing.expectError(error.AlreadyResolved, alias.leaveChecked());
    try std.testing.expectEqual(@as(usize, 1), runtime.no_shift_depth);
    try guard.leaveChecked();
    try std.testing.expectEqual(@as(usize, 0), runtime.no_shift_depth);
}

test "runtime checked deinit rejects active reset" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = void;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{ TestExpectedError, TestUnexpectedError };
    };

    const demo = struct {
        var runtime_ptr: *Runtime = undefined;

        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const inner = try reset(demo_spec, runtime_ptr, struct {
                fn nested() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
                    return 7;
                }
            }.nested);
            try std.testing.expectError(error.RuntimeBusy, runtime_ptr.deinitChecked());
            return switch (inner) {
                .complete => |answer| answer,
                .pending, .cancelled => unreachable,
            };
        }
    };

    demo.runtime_ptr = &runtime;
    const outcome = try reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 7), answer),
        .pending, .cancelled => unreachable,
    }
}

test "runtime copied alias is rejected after first use" {
    var runtime = Runtime.init(std.testing.allocator, .{});

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = void;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const outcome = try reset(demo_spec, &runtime, struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            return 7;
        }
    }.body);
    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 7), answer),
        .pending, .cancelled => unreachable,
    }

    var alias = runtime;
    try std.testing.expectError(error.RuntimeAliased, alias.deinitChecked());
    try runtime.deinitChecked();
}

test "runtime checked deinit rejects double teardown and later reset use" {
    var runtime = Runtime.init(std.testing.allocator, .{});

    try runtime.deinitChecked();
    try std.testing.expectError(error.RuntimeDestroyed, runtime.deinitChecked());

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = void;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    try std.testing.expectError(error.RuntimeDestroyed, reset(demo_spec, &runtime, struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            return 7;
        }
    }.body));
}

test "outer prompt token can bubble through an inner reset" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const outer_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = i32;
        /// Resume value type.
        pub const Resume = i32;
        /// Final answer type.
        pub const Answer = i32;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const inner_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = i32;
        /// Resume value type.
        pub const Resume = i32;
        /// Final answer type.
        pub const Answer = i32;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        var runtime_ptr: *Runtime = undefined;

        fn innerBody() ResetError(inner_spec.ErrorSet)!inner_spec.Answer {
            const current = try shift(outer_spec, 41);
            return current + 1;
        }

        fn outerBody() ResetError(outer_spec.ErrorSet)!outer_spec.Answer {
            var inner_outcome = try reset(inner_spec, runtime_ptr, innerBody);
            while (true) switch (inner_outcome) {
                .complete => |answer| return answer,
                .cancelled => return error.Cancelled,
                .pending => |*pending| {
                    const resumed = try shift(outer_spec, pending.request());
                    inner_outcome = try pending.resumeWith(resumed);
                },
            };
        }
    };

    demo.runtime_ptr = &runtime;
    var outcome = try reset(outer_spec, &runtime, demo.outerBody);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try std.testing.expectEqual(@as(i32, 41), pending.request());
            outcome = try pending.resumeWith(41);
        },
    }
    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(i32, 42), answer),
        .pending, .cancelled => unreachable,
    }
}

test "user discontinue can recover across outer-prompt bubbling" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const outer_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = []const u8;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{Stop};
    };

    const inner_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = []const u8;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{Stop};
    };

    const demo = struct {
        var runtime_ptr: *Runtime = undefined;

        fn innerBody() ResetError(inner_spec.ErrorSet)!inner_spec.Answer {
            _ = shift(outer_spec, "first") catch |err| switch (err) {
                error.Stop => {},
                else => return err,
            };
            _ = try shift(outer_spec, "after-stop");
            return 7;
        }

        fn outerBody() ResetError(outer_spec.ErrorSet)!outer_spec.Answer {
            var inner_outcome = try reset(inner_spec, runtime_ptr, innerBody);
            while (true) switch (inner_outcome) {
                .complete => |answer| return answer,
                .cancelled => return error.Cancelled,
                .pending => |*pending| {
                    _ = shift(outer_spec, pending.request()) catch |err| switch (err) {
                        error.Stop => {
                            inner_outcome = try pending.discontinue(error.Stop);
                            continue;
                        },
                        else => return err,
                    };
                    inner_outcome = try pending.proceed();
                },
            };
        }
    };

    demo.runtime_ptr = &runtime;
    var outcome = try reset(outer_spec, &runtime, demo.outerBody);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try std.testing.expectEqualStrings("first", pending.request());
            outcome = try pending.discontinue(error.Stop);
        },
    }
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try std.testing.expectEqualStrings("after-stop", pending.request());
            outcome = try pending.proceed();
        },
    }
    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 7), answer),
        .pending, .cancelled => unreachable,
    }
}

test "terminal cancellation stays terminal across outer-prompt bubbling" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const outer_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = []const u8;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const inner_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = []const u8;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        var runtime_ptr: *Runtime = undefined;

        fn innerBody() ResetError(inner_spec.ErrorSet)!inner_spec.Answer {
            _ = shift(outer_spec, "first") catch |err| switch (err) {
                error.Cancelled => {},
                else => return err,
            };
            _ = try shift(outer_spec, "should-not-happen");
            return 9;
        }

        fn outerBody() ResetError(outer_spec.ErrorSet)!outer_spec.Answer {
            var inner_outcome = try reset(inner_spec, runtime_ptr, innerBody);
            while (true) switch (inner_outcome) {
                .complete => |answer| return answer,
                .cancelled => return error.Cancelled,
                .pending => |*pending| {
                    _ = shift(outer_spec, pending.request()) catch |err| switch (err) {
                        error.Cancelled => {
                            _ = try pending.cancel();
                            unreachable;
                        },
                        else => return err,
                    };
                    inner_outcome = try pending.proceed();
                },
            };
        }
    };

    demo.runtime_ptr = &runtime;
    var outcome = try reset(outer_spec, &runtime, demo.outerBody);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try std.testing.expectEqualStrings("first", pending.request());
            try std.testing.expectError(error.CancellationRecovered, pending.cancel());
        },
    }
}
