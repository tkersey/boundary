const shift = @import("shift");

const NoError = error{};
const Counter = shift.effect.Define(.{
    .mode = shift.PromptMode.resume_then_transform,
    .state_type = i32,
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Transform("get", void, i32),
    },
});

const fake_cap = struct {
    /// Stub generated-family engine context metadata for the forged context.
    pub fn EngineContextType() type {
        return void;
    }
};

const fake_value: fake_cap = .{};

const FakeContext = struct {
    /// Fake capability metadata that mimics one generated-family context.
    pub const capability = fake_cap;
    /// Fake state metadata that mimics one generated-family context.
    pub const StateType = i32;
    /// Fake answer metadata that mimics one generated-family context.
    pub const AnswerType = i32;
    /// Fake error-set metadata that mimics one generated-family context.
    pub const ErrorSetType = NoError;

    _cap: *const fake_cap = &fake_value,
};

/// Trigger the generated-family forged-context compile failure.
pub fn main() anyerror!void {
    var ctx = FakeContext{};
    _ = try Counter.Op(.get).perform(fake_cap, &ctx);
}
