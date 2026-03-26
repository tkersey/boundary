const shift = @import("shift");

comptime {
    _ = shift.Program(42, struct {
        /// Execute this public body hook.
        pub fn body(_: anytype) anyerror!i32 {
            return 0;
        }
    });
}
