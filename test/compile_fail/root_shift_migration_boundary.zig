comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_then_transform, i32, i32, NoError);

    const handler = struct {
        /// Supply the resumed value for the migration-boundary compile-fail probe.
        pub fn resumeValue() i32 {
            return 1;
        }

        /// Preserve the resumed value if canonical shift.shift were still executable.
        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };

    _ = shift.shift(i32, @as(*const DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))), handler);
}
