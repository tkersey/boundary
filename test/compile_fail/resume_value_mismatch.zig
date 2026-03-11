comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(i32, i32, NoError);

    const demo = struct {
        fn handle(k: *shift.Continuation(i32, DemoPrompt)) shift.ResetError(NoError)!i32 {
            return try k.resumeWith("bad");
        }
    };

    const continuation: *shift.Continuation(i32, DemoPrompt) = @ptrFromInt(@alignOf(shift.Continuation(i32, DemoPrompt)));
    _ = demo.handle(continuation);
}
