comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(i32, i32, NoError);

    const demo = struct {
        fn alias(k: *shift.Continuation(i32, DemoPrompt)) void {
            const alias_a = k;
            const alias_b = k;
            _ = alias_a;
            _ = alias_b;
        }
    };

    const continuation: *shift.Continuation(i32, DemoPrompt) = @ptrFromInt(@alignOf(shift.Continuation(i32, DemoPrompt)));
    demo.alias(continuation);
}
