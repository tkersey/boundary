const shift = @import("shift");

const Broken = shift.Decl.family(.{
    .state_type = i32,
    .ops = .{
        shift.Op.Transform("get", void, i32),
        shift.Op.Choice("pick", void, i32),
    },
}, struct {
    state: i32,
});

comptime {
    _ = Broken;
}
