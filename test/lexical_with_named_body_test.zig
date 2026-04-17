const named_body = @import("lexical_with_named_body_support.zig");
const shift = @import("lexical_runtime_internal");
const std = @import("std");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

test "shift.with accepts body run(eff)" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 9)),
    }, struct {
        /// Run the body through the declared one-argument `run` hook.
        pub fn run(eff: anytype) ExecResult(i32) {
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 9), result.value);
}

test "shift.with accepts body run(self, eff)" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 11)),
    }, struct {
        /// Run the body through the declared self-plus-eff `run` hook.
        pub fn run(self: @This(), eff: anytype) ExecResult(i32) {
            _ = self;
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 11), result.value);
}

test "shift.with accepts NamedBody for state handlers" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 9)),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedStateBody", ExecResult(i32), named_body.namedStateBody));

    try std.testing.expectEqual(@as(i32, 19), result.value);
    try std.testing.expectEqual(@as(i32, 10), result.outputs.state);
}

test "shift.with accepts NamedBody helpers when the effect parameter is renamed" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 9)),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedStateBodyWithRenamedEffectParam", ExecResult(i32), named_body.namedStateBodyWithRenamedEffectParam));

    try std.testing.expectEqual(@as(i32, 9), result.value);
    try std.testing.expectEqual(@as(i32, 9), result.outputs.state);
}

test "shift.with accepts NamedBody for reader handlers" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .reader = shift.effect.reader.use(@as(i32, 21)),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedReaderBody", ExecResult(i32), named_body.namedReaderBody));

    try std.testing.expectEqual(@as(i32, 42), result.value);
}

test "shift.with accepts NamedBody for writer handlers" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .writer = shift.effect.writer.use([]const u8, std.testing.allocator),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedWriterBody", ExecResult([]const u8), named_body.namedWriterBody));
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(usize, 2), result.outputs.writer.len);
    try std.testing.expectEqualStrings("a", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("b", result.outputs.writer[1]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "shift.with accepts NamedBody bool literal returns" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 0)),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedBoolLiteralBody", ExecResult(bool), named_body.namedBoolLiteralBody));

    try std.testing.expectEqual(true, result.value);
}

test "shift.with accepts NamedBody usize literal returns" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 0)),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedUsizeLiteralBody", ExecResult(usize), named_body.namedUsizeLiteralBody));

    try std.testing.expectEqual(@as(usize, 1), result.value);
}

test "shift.with accepts NamedBody large usize literal returns" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 0)),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedLargeUsizeLiteralBody", ExecResult(usize), named_body.namedLargeUsizeLiteralBody));

    try std.testing.expectEqual(@as(usize, 5_000_000_000), result.value);
}

test "shift.with accepts NamedBody bool payload literals for state handlers" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(false),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedBoolStateBody", ExecResult(bool), named_body.namedBoolStateBody));

    try std.testing.expectEqual(true, result.value);
    try std.testing.expectEqual(true, result.outputs.state);
}

test "shift.with accepts NamedBody for optional return-now continuations" {
    const return_now_policy = struct {
        /// Return immediately so the continuation stays dormant.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
        }
        /// Preserve the early answer unchanged.
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, return_now_policy),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedOptionalReturnNowBody", ExecResult([]const u8), named_body.namedOptionalReturnNowBody));

    try std.testing.expectEqualStrings("result=early", result.value);
}

test "shift.with accepts NamedBody for optional resumed continuations" {
    const resume_policy = struct {
        /// Resume with the canonical test payload.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
        }
        /// Preserve the resumed answer unchanged.
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, resume_policy),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedOptionalResumeBody", ExecResult([]const u8), named_body.namedOptionalResumeBody));

    try std.testing.expectEqualStrings("answer=42", result.value);
}

test "shift.with accepts NamedBody bool literal continuation answers" {
    const resume_policy = struct {
        /// Resume with the canonical bool payload.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, bool) {
            return shift.effect.choice.Decision(i32, bool).resumeWith(41);
        }
        /// Preserve the resumed bool answer unchanged.
        pub fn afterResume(answer: bool) bool {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, resume_policy),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedOptionalResumeBoolBody", ExecResult(bool), named_body.namedOptionalResumeBoolBody));

    try std.testing.expectEqual(true, result.value);
}

test "shift.with accepts NamedBody usize literal continuation answers" {
    const resume_policy = struct {
        /// Resume with the canonical usize payload.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, usize) {
            return shift.effect.choice.Decision(i32, usize).resumeWith(41);
        }
        /// Preserve the resumed usize answer unchanged.
        pub fn afterResume(answer: usize) usize {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, resume_policy),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedOptionalResumeUsizeBody", ExecResult(usize), named_body.namedOptionalResumeUsizeBody));

    try std.testing.expectEqual(@as(usize, 1), result.value);
}

test "shift.with accepts NamedBody hexadecimal usize literal continuation answers" {
    const resume_policy = struct {
        /// Resume with the canonical hexadecimal usize payload.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, usize) {
            return shift.effect.choice.Decision(i32, usize).resumeWith(41);
        }
        /// Preserve the resumed hexadecimal usize answer unchanged.
        pub fn afterResume(answer: usize) usize {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, resume_policy),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedOptionalResumeHexUsizeBody", ExecResult(usize), named_body.namedOptionalResumeHexUsizeBody));

    try std.testing.expectEqual(@as(usize, 0xff), result.value);
}

test "shift.with accepts NamedBody large usize literal continuation answers" {
    const resume_policy = struct {
        /// Resume with the canonical large usize payload.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, usize) {
            return shift.effect.choice.Decision(i32, usize).resumeWith(41);
        }
        /// Preserve the resumed large usize answer unchanged.
        pub fn afterResume(answer: usize) usize {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, resume_policy),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedOptionalResumeLargeUsizeBody", ExecResult(usize), named_body.namedOptionalResumeLargeUsizeBody));

    try std.testing.expectEqual(@as(usize, 5_000_000_000), result.value);
}

test "shift.with accepts NamedBody for generated choice continuations" {
    const Picker = shift.effect.Define(.{
        .state_type = void,
        .ops = .{
            shift.effect.ops.Choice("pick", i32, i32),
        },
    });

    const handler = struct {
        /// Resume the generated choice with the provided payload.
        pub fn pick(_: *@This(), value: i32) shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(value);
        }
        /// Preserve the resumed choice answer unchanged.
        pub fn afterPick(_: *@This(), answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedGeneratedChoiceBody", ExecResult([]const u8), named_body.namedGeneratedChoiceBody));

    try std.testing.expectEqualStrings("answer=42", result.value);
}

test "shift.with accepts NamedBody for underscored generated choice after hooks" {
    const Picker = shift.effect.Define(.{
        .state_type = void,
        .ops = .{
            shift.effect.ops.Choice("pick_item", i32, i32),
        },
    });

    const transcript = struct {
        threadlocal var after_called = false;
    };

    const handler = struct {
        /// Resume the generated choice with the provided payload.
        pub fn pick_item(_: *@This(), value: i32) shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(value);
        }
        /// Preserve the resumed choice answer unchanged.
        // zlinter-disable-next-line function_naming - this regression witness must spell the generated underscored after-hook exactly.
        pub fn afterPick_Item(_: *@This(), answer: []const u8) []const u8 {
            transcript.after_called = true;
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    transcript.after_called = false;

    const result = try shift.withAt(@src(), &runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, shift.NamedBody("test/lexical_with_named_body_support.zig", "namedGeneratedChoiceUnderscoreBody", ExecResult([]const u8), named_body.namedGeneratedChoiceUnderscoreBody));

    try std.testing.expect(transcript.after_called);
    try std.testing.expectEqualStrings("answer=42", result.value);
}
