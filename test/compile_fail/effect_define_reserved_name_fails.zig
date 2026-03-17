const prompt_support = @import("prompt_support");
const shift = @import("shift");

const Broken = shift.effect.Define(.{
    .mode = prompt_support.PromptMode.resume_then_transform,
    .state_type = i32,
    .error_set_type = error{},
    .ops = .{
        shift.effect.ops.Transform("handle", void, i32),
    },
});

/// Trigger the generated-family reserved-name compile failure.
pub fn main() void {
    _ = Broken;
}
