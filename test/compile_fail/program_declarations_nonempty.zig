const shift = @import("shift");

comptime {
    _ = shift.Program(.{}, struct {
        pub fn body(_: anytype) !i32 {
            return 0;
        }
    });
}
