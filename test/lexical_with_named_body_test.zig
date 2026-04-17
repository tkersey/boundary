const named_body = @import("lexical_with_named_body_basic_support.zig");
const shift = @import("lexical_runtime_internal");
const std = @import("std");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

test "shift.with accepts NamedBody for state handlers" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 9)),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedStateBody", ExecResult(i32), named_body.namedStateBody));

    try std.testing.expectEqual(@as(i32, 19), result.value);
    try std.testing.expectEqual(@as(i32, 10), result.outputs.state);
}

test "shift.with accepts NamedBody function pointers for state handlers" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 9)),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedStateBody", ExecResult(i32), &named_body.namedStateBody));

    try std.testing.expectEqual(@as(i32, 19), result.value);
    try std.testing.expectEqual(@as(i32, 10), result.outputs.state);
}

test "shift.with accepts NamedBody helpers when the effect parameter is renamed" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 9)),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedStateBodyWithRenamedEffectParam", ExecResult(i32), named_body.namedStateBodyWithRenamedEffectParam));

    try std.testing.expectEqual(@as(i32, 9), result.value);
    try std.testing.expectEqual(@as(i32, 9), result.outputs.state);
}

test "shift.with accepts NamedBody for reader handlers" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .reader = shift.effect.reader.use(@as(i32, 21)),
    }, shift.NamedBody("test/lexical_with_named_body_basic_support.zig", "namedReaderBody", ExecResult(i32), named_body.namedReaderBody));

    try std.testing.expectEqual(@as(i32, 42), result.value);
}

test "shift.with accepts NamedBody for writer handlers" {
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
