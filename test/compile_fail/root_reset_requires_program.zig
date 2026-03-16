comptime {
    const shift = @import("shift");
    const prompt_support = shift.internal;
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, usize, usize, NoError);

    const legacy = struct {
        fn body() shift.ResetError(NoError)!usize {
            return 7;
        }
    };

    _ = prompt_support.run(
        @as(*shift.Runtime, @ptrFromInt(@alignOf(shift.Runtime))),
        @as(*DemoPrompt, @ptrFromInt(@alignOf(DemoPrompt))),
        legacy.body,
    );
}
