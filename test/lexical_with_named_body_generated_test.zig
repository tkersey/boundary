const named_body = @import("lexical_with_named_body_generated_support.zig");
const shift = @import("lexical_runtime_internal");
const std = @import("std");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
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
    }, shift.NamedBody("test/lexical_with_named_body_generated_support.zig", "namedGeneratedChoiceBody", ExecResult([]const u8), named_body.namedGeneratedChoiceBody));

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
    }, shift.NamedBody("test/lexical_with_named_body_generated_support.zig", "namedGeneratedChoiceUnderscoreBody", ExecResult([]const u8), named_body.namedGeneratedChoiceUnderscoreBody));

    try std.testing.expect(transcript.after_called);
    try std.testing.expectEqualStrings("answer=42", result.value);
}

test "shift.with accepts NamedBody for legacy camel-cased generated choice after hooks" {
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
        /// Preserve compatibility with legacy camel-cased generated after-hook names.
        pub fn afterPickItem(_: *@This(), answer: []const u8) []const u8 {
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
