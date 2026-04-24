const ability = @import("ability");
const std = @import("std");

fn ExecResult(comptime T: type) type {
    return (ability.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

test "ability.with accepts body run(eff)" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 9)),
    }, struct {
        /// Run the body through the declared one-argument `run` hook.
        pub fn run(eff: anytype) ExecResult(i32) {
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 9), result.value);
}

test "ability.with accepts body run(self, eff)" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 11)),
    }, struct {
        /// Run the body through the declared self-plus-eff `run` hook.
        pub fn run(self: @This(), eff: anytype) ExecResult(i32) {
            _ = self;
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 11), result.value);
}
