comptime {
    const prompt_support = @import("prompt_support");
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.direct_return, i32, i32, NoError);

    const wrong_mode_handler = struct {
        /// Deliberately provide the wrong protocol for a direct-return prompt.
        pub fn resumeValue() i32 {
            return 1;
        }

        /// Deliberately provide the wrong protocol for a direct-return prompt.
        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };

    _ = prompt_support.frontend.perform(i32, @as(*const DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))), wrong_mode_handler);
}
