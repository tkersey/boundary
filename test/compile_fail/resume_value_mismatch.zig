comptime {
    const shift = @import("shift");
    const tag = struct {};
    const NoError = error{};

    const demo = struct {
        fn handle(k: *shift.Continuation(i32, tag, i32, NoError)) shift.ResetError(NoError)!i32 {
            return try k.resumeWith("bad");
        }
    };

    const continuation: *shift.Continuation(i32, tag, i32, NoError) = @ptrFromInt(@alignOf(shift.Continuation(i32, tag, i32, NoError)));
    _ = demo.handle(continuation);
}
