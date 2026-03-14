const shift = @import("shift");

const NoError = error{};
const fake_cap = struct {
    /// Fake manager metadata that mimics the real capability shape.
    pub fn ManagerType() type {
        return struct {
            /// Acquire a forged resource value.
            pub fn acquire() i32 {
                return 1;
            }

            /// Release the forged resource value.
            pub fn release(_: i32) void {
                // Intentionally empty for this forged manager.
            }
        };
    }
};
const fake_value: fake_cap = .{};

const FakeContext = struct {
    /// Fake capability metadata that mimics the real context shape.
    pub const capability = fake_cap;
    /// Fake resource metadata that mimics the real context shape.
    pub const StateType = i32;
    /// Fake answer metadata that mimics the real context shape.
    pub const AnswerType = i32;
    /// Fake error-set metadata that mimics the real context shape.
    pub const ErrorSetType = NoError;

    _cap: *const fake_cap = &fake_value,
};

/// Attempt to pass a forged resource context-shaped struct to the API.
pub fn main() anyerror!void {
    var ctx = FakeContext{};
    _ = try shift.effect.resource.acquire(fake_cap, &ctx);
}
