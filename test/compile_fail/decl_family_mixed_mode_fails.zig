const shift = @import("shift");

const Broken = shift.Decl.family(.{
    .state_type = i32,
    .ops = .{
        shift.Ops.Transform("get", void, i32),
        shift.Ops.Choice("pick", void, i32),
    },
}, struct {
    state: i32,
});

comptime {
    _ = Broken;
}
