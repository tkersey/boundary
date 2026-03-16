const shift = @import("shift");
const prompt_support = shift.internal;

const Broken = shift.effect.Define(.{
    .mode = prompt_support.PromptMode.resume_then_transform,
    .state_type = i32,
    .error_set_type = error{},
    .ops = .{
        shift.effect.ops.Transform("get", void, i32),
        shift.effect.ops.Choice("pick", void, i32),
    },
});

/// Trigger the generated-family mixed-mode compile failure.
pub fn main() void {
    _ = Broken;
}
