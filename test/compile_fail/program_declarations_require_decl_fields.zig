const shift = @import("shift");

comptime {
    _ = shift.Program(.{
        .bad = struct {}{},
    }, struct {
        /// Execute this public body hook.
        pub fn body(_: anytype) anyerror!i32 {
            return 0;
        }
    });
}
