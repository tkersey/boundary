comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_then_transform, usize, usize, NoError);

    const legacy = struct {
        fn body() shift.ResetError(NoError)!usize {
            return 7;
        }
    };

    _ = shift.reset(
        @as(*shift.Runtime, @ptrFromInt(@alignOf(shift.Runtime))),
        @as(*DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))),
        legacy.body,
    );
}
