comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(i32, []const u8, NoError);

    const Borrowed = struct {
        continuation: *shift.Continuation(i32, DemoPrompt),
    };

    const Owner = struct {
        continuation: *shift.Continuation(i32, DemoPrompt),

        fn borrow(self: *@This()) Borrowed {
            return .{ .continuation = self.continuation };
        }
    };

    const continuation: *shift.Continuation(i32, DemoPrompt) = @ptrFromInt(@alignOf(shift.Continuation(i32, DemoPrompt)));
    var owner = Owner{ .continuation = continuation };
    const borrowed = owner.borrow();
    var saved: ?Borrowed = borrowed;
    _ = &saved;
}
