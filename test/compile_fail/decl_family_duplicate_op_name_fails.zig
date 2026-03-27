const shift = @import("shift");

const Broken = shift.Decl.family(.{
    .state_type = i32,
    .ops = .{
        shift.Ops.Transform("dup", void, i32),
        shift.Ops.Transform("dup", i32, void),
    },
}, struct {
    state: i32,
});

comptime {
    _ = Broken;
}
