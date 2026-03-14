const shift = @import("shift");

const NoError = error{};
const fake_cap = struct {};
const fake_value: fake_cap = .{};

const FakeContext = struct {
    /// Fake capability metadata that mimics the real context shape.
    pub const capability = fake_cap;
    /// Fake state metadata that mimics the real context shape.
    pub const StateType = i32;
    /// Fake answer metadata that mimics the real context shape.
    pub const AnswerType = i32;
    /// Fake error-set metadata that mimics the real context shape.
    pub const ErrorSetType = NoError;

    _cap: *const fake_cap = &fake_value,
};

/// Attempt to pass a forged reader context-shaped struct to the reader API.
pub fn main() anyerror!void {
    var ctx = FakeContext{};
    _ = try shift.effect.reader.ask(fake_cap, &ctx);
}
