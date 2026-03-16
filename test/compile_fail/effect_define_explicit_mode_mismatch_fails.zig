const shift = @import("shift");
const prompt_support = shift.internal;

const Broken = shift.effect.Define(.{
    .mode = prompt_support.PromptMode.direct_return,
    .state_type = i32,
    .error_set_type = error{},
    .ops = .{
        shift.effect.ops.Transform("get", void, i32),
    },
});

/// Trigger the generated-family explicit-mode mismatch compile failure.
pub fn main() void {
    _ = Broken;
}
