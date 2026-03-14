const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ping = shift.algebraic.TransformOp("ping", void, i32);
const demo = shift.algebraic.Program(i32, NoError, .{ping});

const no_state = struct {};

const configured = demo.handlers(.{
    shift.algebraic.handleTransform(ping, no_state{}, struct {
        /// Supply the transform witness value.
        pub fn resumeValue(_: no_state, _: void) i32 {
            return 41;
        }

        /// Trigger the wrong-afterResume-type compile failure.
        pub fn afterResume(_: no_state, _: i32) i64 {
            return 42;
        }
    }),
});

const body = struct {
    /// Provide the compile-fail wrong-afterResume-type witness body.
    pub fn body(ctx: *@TypeOf(configured).Context) shift.ResetError(NoError)!i32 {
        const value = try ctx.perform(ping, {});
        return value + 1;
    }
};

/// Trigger the compile-fail wrong-afterResume-type witness.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    _ = try configured.run(&runtime, body);
}
