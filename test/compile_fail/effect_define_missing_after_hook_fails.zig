const shift = @import("shift");
const prompt_support = shift.internal;
const std = @import("std");

const NoError = error{};
const Counter = shift.effect.Define(.{
    .mode = prompt_support.PromptMode.resume_then_transform,
    .state_type = i32,
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Transform("get", void, i32),
    },
});

const BadHandler = struct {
    state: i32,

    /// Read the generated state cell once.
    pub fn get(self: *@This()) i32 {
        return self.state;
    }
};

/// Trigger the generated-family missing-after-hook compile failure.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var instance = Counter.Instance.init();
    _ = try Counter.handle(i32, &runtime, &instance, BadHandler{ .state = 0 }, struct {
        /// Attempt to use the generated transform family without an after hook.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            return try Counter.Op(.get).perform(Cap, ctx);
        }
    });
}
