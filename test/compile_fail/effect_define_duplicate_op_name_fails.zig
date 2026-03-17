const prompt_support = @import("prompt_support");
const shift = @import("shift");

const Broken = shift.effect.Define(.{
    .mode = prompt_support.PromptMode.resume_then_transform,
    .state_type = i32,
    .error_set_type = error{},
    .ops = .{
        shift.effect.ops.Transform("dup", void, i32),
        shift.effect.ops.Transform("dup", i32, void),
    },
});

/// Trigger the generated-family duplicate-op-name compile failure.
pub fn main() void {
    _ = Broken;
}
