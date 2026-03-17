const prompt_support = @import("prompt_support");
const shift = @import("shift");

const NoError = error{};
const fake_cap = struct {
    /// Fake policy metadata that mimics the real capability shape.
    pub fn PolicyType() type {
        return struct {
            /// Supply a resumptive branch for the forged optional policy.
            pub fn resumeOrReturn() prompt_support.ResumeOrReturn(i32, i32) {
                return prompt_support.ResumeOrReturn(i32, i32).resumeWith(1);
            }

            /// Preserve the resumed answer for the forged optional policy.
            pub fn afterResume(value: i32) i32 {
                return value;
            }
        };
    }
};
const fake_value: fake_cap = .{};

const FakeContext = struct {
    /// Fake capability metadata that mimics the real context shape.
    pub const capability = fake_cap;
    /// Fake resume metadata that mimics the real context shape.
    pub const StateType = i32;
    /// Fake answer metadata that mimics the real context shape.
    pub const AnswerType = i32;
    /// Fake error-set metadata that mimics the real context shape.
    pub const ErrorSetType = NoError;

    _cap: *const fake_cap = &fake_value,
};

/// Attempt to pass a forged optional context-shaped struct to the API.
pub fn main() anyerror!void {
    var ctx = FakeContext{};
    _ = try shift.effect.optional.request(fake_cap, &ctx);
}
