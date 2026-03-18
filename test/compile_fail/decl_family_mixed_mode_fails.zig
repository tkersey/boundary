const shift = @import("shift");

const Broken = shift.Decl.family(.{
    .state_type = i32,
    .ops = .{
        shift.Op.transform("get", void, i32),
        shift.Op.choice("pick", void, i32),
    },
}, struct {
    state: i32,
});

comptime {
    _ = Broken;
}
