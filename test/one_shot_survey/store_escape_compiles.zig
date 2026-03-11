comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(i32, i32, NoError);

    const Holder = struct {
        saved: ?*shift.Continuation(i32, DemoPrompt) = null,
    };

    const demo = struct {
        fn store(k: *shift.Continuation(i32, DemoPrompt)) void {
            var holder = Holder{ .saved = k };
            _ = &holder;
        }
    };

    const continuation: *shift.Continuation(i32, DemoPrompt) = @ptrFromInt(@alignOf(shift.Continuation(i32, DemoPrompt)));
    demo.store(continuation);
}
