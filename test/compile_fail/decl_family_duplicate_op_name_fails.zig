const shift = @import("shift");

const Broken = shift.Decl.family(.{
    .state_type = i32,
    .ops = .{
        shift.Op.Transform("dup", void, i32),
        shift.Op.Transform("dup", i32, void),
    },
}, struct {
    state: i32,
});

comptime {
    _ = Broken;
}
