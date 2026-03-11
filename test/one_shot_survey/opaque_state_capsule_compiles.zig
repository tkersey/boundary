comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(i32, []const u8, NoError);

    const Capsule = struct {
        continuation: *shift.Continuation(i32, DemoPrompt),
        hidden: u8,
    };

    const continuation: *shift.Continuation(i32, DemoPrompt) = @ptrFromInt(@alignOf(shift.Continuation(i32, DemoPrompt)));
    const capsule = Capsule{ .continuation = continuation, .hidden = 1 };
    const alias = capsule;
    _ = alias;
}
