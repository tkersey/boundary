const example_driver = @import("example_driver");
const shift = @import("shift");
const std = @import("std");

const demo_spec = struct {
    /// Prompt tag for helper contract tests.
    pub const tag = struct {};
    /// The helper test request is a single integer.
    pub const Request = i32;
    /// Resume values are integers.
    pub const Resume = i32;
    /// The body completes with an integer answer.
    pub const Answer = i32;
    /// The helper tests need one user-owned error.
    pub const ErrorSet = error{Stop};
};

const demo = struct {
    fn body() shift.ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
        const current = try shift.shift(demo_spec, 41);
        return current + 1;
    }
};

test "resume decision reaches complete" {
    const resume_handler = struct {
        fn handle(_: *@This(), request: demo_spec.Request) anyerror!example_driver.Decision(demo_spec) {
            return .{ .resume_value = request };
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    var handler: resume_handler = .{};
    const outcome = try example_driver.run(demo_spec, &runtime, demo.body, &handler, resume_handler.handle);
    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(i32, 42), answer),
        .cancelled => unreachable,
    }
}

test "cancel decision reaches terminal cancellation" {
    const cancel_handler = struct {
        fn handle(_: *@This(), _: demo_spec.Request) anyerror!example_driver.Decision(demo_spec) {
            return .{ .cancel = {} };
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    var handler: cancel_handler = .{};
    const outcome = try example_driver.run(demo_spec, &runtime, demo.body, &handler, cancel_handler.handle);
    switch (outcome) {
        .complete => unreachable,
        .cancelled => {},
    }
}

test "discontinue decision propagates user error" {
    const discontinue_handler = struct {
        fn handle(_: *@This(), _: demo_spec.Request) anyerror!example_driver.Decision(demo_spec) {
            return .{ .discontinue = error.Stop };
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    var handler: discontinue_handler = .{};
    try std.testing.expectError(error.Stop, example_driver.run(demo_spec, &runtime, demo.body, &handler, discontinue_handler.handle));
}

test "handler failure drains unresolved token" {
    const failing_handler = struct {
        fn handle(_: *@This(), _: demo_spec.Request) anyerror!example_driver.Decision(demo_spec) {
            return error.HandlerFailed;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});

    var handler: failing_handler = .{};
    try std.testing.expectError(error.HandlerFailed, example_driver.run(demo_spec, &runtime, demo.body, &handler, failing_handler.handle));
    try runtime.deinitChecked();
}
