comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(i32, []const u8, NoError);

    const Left = struct {
        continuation: *shift.Continuation(i32, DemoPrompt),
    };

    const Right = struct {
        continuation: *shift.Continuation(i32, DemoPrompt),
    };

    const Pair = struct {
        left: Left,
        right: Right,
    };

    const continuation: *shift.Continuation(i32, DemoPrompt) = @ptrFromInt(@alignOf(shift.Continuation(i32, DemoPrompt)));
    const pair = Pair{
        .left = .{ .continuation = continuation },
        .right = .{ .continuation = continuation },
    };
    _ = pair;
}
