comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(i32, []const u8, NoError);

    const State = enum { consumed, fresh };

    const Wrapper = struct {
        continuation: *shift.Continuation(i32, DemoPrompt),
        state: State,

        fn markConsumed(self: *@This()) void {
            self.state = .consumed;
        }
    };

    const continuation: *shift.Continuation(i32, DemoPrompt) = @ptrFromInt(@alignOf(shift.Continuation(i32, DemoPrompt)));
    var wrapper = Wrapper{ .continuation = continuation, .state = .fresh };
    const alias = wrapper;
    wrapper.markConsumed();
    _ = alias;
}
