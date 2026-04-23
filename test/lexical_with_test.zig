const shift = @import("shift");
const std = @import("std");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

test "shift.with accepts body run(eff)" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
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

    const result = try shift.with(&runtime, .{
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

test "shift.with accepts named body types without lowering metadata" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const named_body = struct {
        /// Execute the named carrier through the declared one-argument `run` hook.
        pub fn run(eff: anytype) ExecResult(i32) {
            return try eff.state.get();
        }
    };

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(@as(i32, 13)),
    }, named_body);

    try std.testing.expectEqual(@as(i32, 13), result.value);
}
