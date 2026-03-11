comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(i32, []const u8, NoError);

    const Used = struct {
        continuation: *shift.Continuation(i32, DemoPrompt),
    };

    const Fresh = struct {
        continuation: *shift.Continuation(i32, DemoPrompt),

        fn consume(self: @This()) Used {
            return .{ .continuation = self.continuation };
        }
    };

    const continuation: *shift.Continuation(i32, DemoPrompt) = @ptrFromInt(@alignOf(shift.Continuation(i32, DemoPrompt)));
    const fresh = Fresh{ .continuation = continuation };
    const alias_a = fresh;
    const alias_b = fresh;
    _ = alias_a.consume();
    _ = alias_b.consume();
}
