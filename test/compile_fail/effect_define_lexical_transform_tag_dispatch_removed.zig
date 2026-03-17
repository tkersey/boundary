const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const Counter = shift.effect.Define(.{
    .state_type = i32,
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Transform("get", void, i32),
        shift.effect.ops.Transform("set", i32, void),
    },
});

/// Trigger the removed generated lexical transform tag-dispatch compile failure.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    _ = try shift.with(&runtime, .{
        .counter = Counter.use(.{ .handler = struct {
            state: i32 = 5,

            /// Read the current generated counter state.
            pub fn get(self: *@This()) i32 {
                return self.state;
            }

            /// Preserve the enclosing answer after a generated counter read.
            pub fn afterGet(_: *@This(), answer: i32) i32 {
                return answer;
            }

            /// Replace the current generated counter state.
            pub fn set(self: *@This(), value: i32) void {
                self.state = value;
            }

            /// Preserve the enclosing answer after a generated counter write.
            pub fn afterSet(_: *@This(), answer: i32) i32 {
                return answer;
            }
        }{} }),
    }, struct {
        /// Attempt to use the removed generated lexical tag-dispatch transform surface.
        pub fn body(eff: anytype) !i32 {
            return try eff.counter.perform(.get);
        }
    });
}
