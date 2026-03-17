comptime {
    const prompt_support = @import("prompt_support");
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_or_return, i32, i32, NoError);
    const Decision = prompt_support.ResumeOrReturn(i32, i32);

    const bad_handler = struct {
        /// Deliberately use the new protocol with an invalid afterResume signature.
        pub fn resumeOrReturn() Decision {
            return Decision.resumeWith(1);
        }

        /// Deliberately provide the wrong parameter type for the new mode.
        pub fn afterResume(_: []const u8) i32 {
            return 2;
        }
    };

    _ = prompt_support.frontend.perform(i32, @as(*const DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))), bad_handler);
}
