const shift = @import("shift");

const NoError = error{};
const fake_cap = struct {
    /// Fake catch metadata that mimics the real capability shape.
    pub fn CatchType() type {
        return struct {
            /// Convert the forged payload into the enclosing answer.
            pub fn directReturn(payload: i32) i32 {
                return payload;
            }
        };
    }
};
const fake_value: fake_cap = .{};

const FakeContext = struct {
    /// Fake capability metadata that mimics the real context shape.
    pub const capability = fake_cap;
    /// Fake payload metadata that mimics the real context shape.
    pub const StateType = i32;
    /// Fake answer metadata that mimics the real context shape.
    pub const AnswerType = i32;
    /// Fake error-set metadata that mimics the real context shape.
    pub const ErrorSetType = NoError;

    _cap: *const fake_cap = &fake_value,
};

/// Attempt to pass a forged exception context-shaped struct to the API.
pub fn main() anyerror!void {
    var ctx = FakeContext{};
    try shift.effect.exception.throw(fake_cap, &ctx, 1);
}
