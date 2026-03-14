const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ping = shift.algebraic.TransformOp("ping", void, i32);

const no_state = struct {};

const configured = shift.algebraic.Program(i32, NoError, .{ping}).handlers(.{
    shift.algebraic.handleChoice(ping, no_state{}, struct {
        /// Trigger the wrong-builder-mode compile failure.
        pub fn resumeOrReturn(_: no_state, _: void) shift.ResumeOrReturn(i32, i32) {
            return shift.ResumeOrReturn(i32, i32).resumeWith(0);
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    }),
});

const body = struct {
    /// Provide the compile-fail wrong-builder-mode witness body.
    pub fn body(_: *@TypeOf(configured).Context) shift.ResetError(NoError)!i32 {
        return 0;
    }
};

/// Trigger the compile-fail wrong-builder-mode witness.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    _ = try configured.run(&runtime, body);
}
