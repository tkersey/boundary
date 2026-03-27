comptime {
    const prompt_support = @import("prompt_support");
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, i32, i32, NoError);

    const bad_handler = struct {
        /// Provide the resumptive value for this public hook.
        pub fn resumeValue() []const u8 {
            return "bad";
        }

        /// Finish this public resumed path.
        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };

    _ = prompt_support.frontend.perform(i32, @as(*const DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))), bad_handler);
}
