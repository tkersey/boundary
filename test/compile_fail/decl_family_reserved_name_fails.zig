const shift = @import("shift");

const Broken = shift.Decl.family(.{
    .state_type = i32,
    .ops = .{
        shift.Ops.Transform("handle", void, i32),
    },
}, struct {
    state: i32,
});

comptime {
    _ = Broken;
}
