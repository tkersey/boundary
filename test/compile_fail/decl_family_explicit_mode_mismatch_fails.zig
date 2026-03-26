const prompt_support = @import("prompt_support");
const shift = @import("shift");

const Broken = shift.Decl.family(.{
    .mode = prompt_support.PromptMode.direct_return,
    .state_type = i32,
    .ops = .{
        shift.Ops.Transform("get", void, i32),
    },
}, struct {
    state: i32,
});

comptime {
    _ = Broken;
}
