comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_or_return, i32, i32, NoError);

    const bad_handler = struct {
        /// Deliberately return the wrong helper type for the new mode.
        pub fn resumeOrReturn() []const u8 {
            return "bad";
        }
    };

    _ = shift.shift(i32, @as(*const DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))), bad_handler);
}
