comptime {
    const shift = @import("shift");
    const prompt_support = shift.internal;
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, i32, i32, NoError);

    const bad_handler = struct {
        /// Deliberately wrong resume type for the compile-fail probe.
        pub fn resumeValue() []const u8 {
            return "bad";
        }

        /// Preserve the resumed value if the protocol type were correct.
        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };

    _ = prompt_support.frontend.perform(i32, @as(*const DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))), bad_handler);
}
