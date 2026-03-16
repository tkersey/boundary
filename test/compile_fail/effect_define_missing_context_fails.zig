const shift = @import("shift");

const Counter = shift.effect.Define(.{
    .mode = shift.PromptMode.resume_then_transform,
    .state_type = i32,
    .error_set_type = error{},
    .ops = .{
        shift.effect.ops.Transform("get", void, i32),
    },
});

const fake_cap = struct {};

/// Trigger the generated-family missing-context compile failure.
pub fn main() anyerror!void {
    _ = try Counter.Op(.get).perform(fake_cap, 123);
}
