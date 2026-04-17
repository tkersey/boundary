// zlinter-disable require_doc_comment - this registry exposes public nested handlers and exported case tables as comptime-visible NamedBody conformance witnesses.
// zlinter-disable no_literal_args - exact bool witnesses in this registry intentionally assert the concrete true or false result values.
const shift = @import("lexical_runtime_internal");
const std = @import("std");

pub const Case = struct {
    name: []const u8,
    run: *const fn () anyerror!void,
};

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

fn runStateCase() !void {
    const named_body = @import("lexical_with_named_body_basic_support.zig");
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 9)),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedStateBody", ExecResult(i32), named_body.namedStateBody));

    try std.testing.expectEqual(@as(i32, 19), result.value);
    try std.testing.expectEqual(@as(i32, 10), result.outputs.state);
}

fn runRenamedStateCase() !void {
    const named_body = @import("lexical_with_named_body_basic_support.zig");
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 9)),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedStateBodyWithRenamedEffectParam", ExecResult(i32), named_body.namedStateBodyWithRenamedEffectParam));

    try std.testing.expectEqual(@as(i32, 9), result.value);
    try std.testing.expectEqual(@as(i32, 9), result.outputs.state);
}

fn runReaderCase() !void {
    const named_body = @import("lexical_with_named_body_basic_support.zig");
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .reader = shift.effect.reader.use(@as(i32, 21)),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedReaderBody", ExecResult(i32), named_body.namedReaderBody));

    try std.testing.expectEqual(@as(i32, 42), result.value);
}

fn runWriterCase() !void {
    const named_body = @import("lexical_with_named_body_basic_support.zig");
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .writer = shift.effect.writer.use([]const u8, std.testing.allocator),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedWriterBody", ExecResult([]const u8), named_body.namedWriterBody));
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(usize, 2), result.outputs.writer.len);
    try std.testing.expectEqualStrings("a", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("b", result.outputs.writer[1]);
    try std.testing.expectEqualStrings("done", result.value);
}

fn runBoolLiteralCase() !void {
    const named_body = @import("lexical_with_named_body_basic_support.zig");
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 0)),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedBoolLiteralBody", ExecResult(bool), named_body.namedBoolLiteralBody));

    try std.testing.expectEqual(true, result.value);
}

fn runUsizeLiteralCase() !void {
    const named_body = @import("lexical_with_named_body_basic_support.zig");
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 0)),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedUsizeLiteralBody", ExecResult(usize), named_body.namedUsizeLiteralBody));

    try std.testing.expectEqual(@as(usize, 1), result.value);
}

fn runLargeUsizeLiteralCase() !void {
    const named_body = @import("lexical_with_named_body_basic_support.zig");
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 0)),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedLargeUsizeLiteralBody", ExecResult(usize), named_body.namedLargeUsizeLiteralBody));

    try std.testing.expectEqual(@as(usize, 5_000_000_000), result.value);
}

fn runBoolStateCase() !void {
    const named_body = @import("lexical_with_named_body_basic_support.zig");
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(false),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedBoolStateBody", ExecResult(bool), named_body.namedBoolStateBody));

    try std.testing.expectEqual(true, result.value);
    try std.testing.expectEqual(true, result.outputs.state);
}

fn runOptionalReturnNowCase() !void {
    const named_body = @import("lexical_with_named_body_optional_support.zig");
    const policy = struct {
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
        }
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalReturnNowBody", ExecResult([]const u8), named_body.namedOptionalReturnNowBody));
    try std.testing.expectEqualStrings("result=early", result.value);
}

fn runOptionalResumeCase() !void {
    const named_body = @import("lexical_with_named_body_optional_support.zig");
    const policy = struct {
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
        }
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalResumeBody", ExecResult([]const u8), named_body.namedOptionalResumeBody));
    try std.testing.expectEqualStrings("answer=42", result.value);
}

fn runOptionalResumeBoolCase() !void {
    const named_body = @import("lexical_with_named_body_optional_support.zig");
    const policy = struct {
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, bool) {
            return shift.effect.choice.Decision(i32, bool).resumeWith(41);
        }
        pub fn afterResume(answer: bool) bool {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalResumeBoolBody", ExecResult(bool), named_body.namedOptionalResumeBoolBody));
    try std.testing.expectEqual(true, result.value);
}

fn runOptionalResumeUsizeCase() !void {
    const named_body = @import("lexical_with_named_body_optional_support.zig");
    const policy = struct {
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, usize) {
            return shift.effect.choice.Decision(i32, usize).resumeWith(41);
        }
        pub fn afterResume(answer: usize) usize {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalResumeUsizeBody", ExecResult(usize), named_body.namedOptionalResumeUsizeBody));
    try std.testing.expectEqual(@as(usize, 1), result.value);
}

fn runOptionalResumeHexCase() !void {
    const named_body = @import("lexical_with_named_body_optional_support.zig");
    const policy = struct {
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, usize) {
            return shift.effect.choice.Decision(i32, usize).resumeWith(41);
        }
        pub fn afterResume(answer: usize) usize {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalResumeHexUsizeBody", ExecResult(usize), named_body.namedOptionalResumeHexUsizeBody));
    try std.testing.expectEqual(@as(usize, 0xff), result.value);
}

fn runOptionalResumeLargeCase() !void {
    const named_body = @import("lexical_with_named_body_optional_support.zig");
    const policy = struct {
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, usize) {
            return shift.effect.choice.Decision(i32, usize).resumeWith(41);
        }
        pub fn afterResume(answer: usize) usize {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, shift.NamedBody("test/lexical_with_named_body_optional_support.zig", "namedOptionalResumeLargeUsizeBody", ExecResult(usize), named_body.namedOptionalResumeLargeUsizeBody));
    try std.testing.expectEqual(@as(usize, 5_000_000_000), result.value);
}

fn runGeneratedChoiceCase() !void {
    const named_body = @import("lexical_with_named_body_generated_support.zig");
    const Picker = shift.effect.Define(.{
        .state_type = void,
        .ops = .{
            shift.effect.ops.Choice("pick", i32, i32),
        },
    });

    const handler = struct {
        pub fn pick(_: *@This(), value: i32) shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(value);
        }
        pub fn afterPick(_: *@This(), answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try shift.withAt(@src(), &runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, shift.NamedBody("test/lexical_with_named_body_generated_support.zig", "namedGeneratedChoiceBody", ExecResult([]const u8), named_body.namedGeneratedChoiceBody));
    try std.testing.expectEqualStrings("answer=42", result.value);
}

fn runGeneratedChoiceUnderscoreCase() !void {
    const named_body = @import("lexical_with_named_body_generated_support.zig");
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
        pub fn pick_item(_: *@This(), value: i32) shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(value);
        }
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
    }, shift.NamedBody("test/lexical_with_named_body_generated_support.zig", "namedGeneratedChoiceUnderscoreBody", ExecResult([]const u8), named_body.namedGeneratedChoiceUnderscoreBody));
    try std.testing.expect(transcript.after_called);
    try std.testing.expectEqualStrings("answer=42", result.value);
}

pub const smoke_cases = [_]Case{
    .{ .name = "state", .run = runStateCase },
    .{ .name = "optional_resume", .run = runOptionalResumeCase },
    .{ .name = "generated_choice_underscore", .run = runGeneratedChoiceUnderscoreCase },
};

pub const full_cases = [_]Case{
    .{ .name = "state", .run = runStateCase },
    .{ .name = "state_renamed", .run = runRenamedStateCase },
    .{ .name = "reader", .run = runReaderCase },
    .{ .name = "writer", .run = runWriterCase },
    .{ .name = "bool_literal", .run = runBoolLiteralCase },
    .{ .name = "usize_literal", .run = runUsizeLiteralCase },
    .{ .name = "large_usize_literal", .run = runLargeUsizeLiteralCase },
    .{ .name = "bool_state", .run = runBoolStateCase },
    .{ .name = "optional_return_now", .run = runOptionalReturnNowCase },
    .{ .name = "optional_resume", .run = runOptionalResumeCase },
    .{ .name = "optional_resume_bool", .run = runOptionalResumeBoolCase },
    .{ .name = "optional_resume_usize", .run = runOptionalResumeUsizeCase },
    .{ .name = "optional_resume_hex", .run = runOptionalResumeHexCase },
    .{ .name = "optional_resume_large", .run = runOptionalResumeLargeCase },
    .{ .name = "generated_choice", .run = runGeneratedChoiceCase },
    .{ .name = "generated_choice_underscore", .run = runGeneratedChoiceUnderscoreCase },
};
