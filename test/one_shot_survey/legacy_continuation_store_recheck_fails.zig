comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_then_transform, i32, i32, NoError);

    const StoreBox = struct {
        saved: ?*shift.Continuation(i32, DemoPrompt) = null,
    };

    _ = StoreBox;
}
