comptime {
    const prompt_support = @import("prompt_support");
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, i32, i32, NoError);

    const StoreBox = struct {
        saved: ?*shift.Continuation(i32, DemoPrompt) = null,
    };

    _ = StoreBox;
}
