const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ping = shift.algebraic.TransformOp("ping", void, i32);
const pong = shift.algebraic.TransformOp("pong", void, i32);
const demo = shift.algebraic.Program(i32, NoError, .{ping});

const no_state = struct {};

const configured = demo.handlers(.{
    shift.algebraic.handleTransform(ping, no_state{}, struct {
        /// Supply the transform witness value.
        pub fn resumeValue(_: no_state, _: void) i32 {
            return 1;
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    }),
});

const body = struct {
    /// Provide the compile-fail undeclared-op witness body.
    pub fn body(ctx: *@TypeOf(configured).Context) shift.ResetError(NoError)!i32 {
        return try ctx.perform(pong, {});
    }
};

/// Trigger the compile-fail undeclared-op witness.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    _ = try configured.run(&runtime, body);
}
