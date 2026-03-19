const shift = @import("shift");

comptime {
    _ = shift.Program(.{
        .bad = struct {}{},
    }, struct {
        pub fn body(_: anytype) !i32 {
            return 0;
        }
    });
}
