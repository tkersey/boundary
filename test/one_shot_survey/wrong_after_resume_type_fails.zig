comptime {
    const prompt_support = @import("prompt_support");
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, i32, i32, NoError);

    const bad_handler = struct {
        /// Supply a valid resume type so the signature failure isolates to afterResume.
        pub fn resumeValue() i32 {
            return 1;
        }

        /// Deliberately wrong parameter type for the compile-time probe.
        pub fn afterResume(_: []const u8) i32 {
            return 2;
        }
    };

    _ = prompt_support.frontend.perform(i32, @as(*const DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))), bad_handler);
}
