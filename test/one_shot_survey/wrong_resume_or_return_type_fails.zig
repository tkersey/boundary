comptime {
    const shift = @import("shift");
    const prompt_support = shift.internal;
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_or_return, i32, i32, NoError);

    const bad_handler = struct {
        /// Deliberately return the wrong helper type for the new mode.
        pub fn resumeOrReturn() []const u8 {
            return "bad";
        }
    };

    _ = prompt_support.frontend.perform(i32, @as(*const DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))), bad_handler);
}
