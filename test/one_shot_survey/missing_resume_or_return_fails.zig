comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_or_return, i32, i32, NoError);

    const bad_handler = struct {
        /// Deliberately provide the old resume protocol for the new mode.
        pub fn resumeValue() i32 {
            return 1;
        }

        /// Deliberately provide the old resume protocol for the new mode.
        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };

    _ = shift.frontend.perform(i32, @as(*const DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))), bad_handler);
}
