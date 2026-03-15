comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_then_transform, i32, i32, NoError);

    const bad_handler = struct {
        /// Supply only half of the required protocol to prove compile-time rejection.
        pub fn resumeValue() i32 {
            return 1;
        }
    };

    _ = shift.frontend.perform(i32, @as(*const DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))), bad_handler);
}
