const named_body = @import("lexical_with_named_body_optional_support.zig");
const shift = @import("lexical_runtime_internal");
const std = @import("std");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
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
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalReturnNowBody", ExecResult([]const u8), named_body.namedOptionalReturnNowBody));

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
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalResumeBody", ExecResult([]const u8), named_body.namedOptionalResumeBody));

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
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalResumeBoolBody", ExecResult(bool), named_body.namedOptionalResumeBoolBody));

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
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalResumeUsizeBody", ExecResult(usize), named_body.namedOptionalResumeUsizeBody));

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
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalResumeHexUsizeBody", ExecResult(usize), named_body.namedOptionalResumeHexUsizeBody));

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
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalResumeLargeUsizeBody", ExecResult(usize), named_body.namedOptionalResumeLargeUsizeBody));

    try std.testing.expectEqual(@as(usize, 5_000_000_000), result.value);
}
