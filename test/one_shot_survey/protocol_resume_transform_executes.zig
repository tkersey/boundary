const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const DemoPrompt = shift.Prompt(.resume_then_transform, i32, i32, NoError);

const demo = struct {
    var prompt_ptr: ?*const DemoPrompt = null;

    const handle = struct {
        /// Supply the resumed value for the runtime survey smoke check.
        pub fn resumeValue() i32 {
            return 1;
        }

        /// Preserve the resumed value on the enclosing answer path.
        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };

    fn body() shift.ResetError(NoError)!i32 {
        const value = try shift.shift(i32, prompt_ptr.?, handle);
        return value + 1;
    }
};

/// Execute the runtime smoke-check fixture for the resume-then-transform protocol.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;

    const answer = try shift.reset(&runtime, &prompt, demo.body);
    if (answer != 2) return error.UnexpectedAnswer;
}
