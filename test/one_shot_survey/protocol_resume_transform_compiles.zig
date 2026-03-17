const prompt_support = @import("prompt_support");

const NoError = error{};
const DemoPrompt = prompt_support.Prompt(.resume_then_transform, i32, i32, NoError);

const demo = struct {
    const handle = struct {
        /// Supply the resumed value for the protocol surface smoke check.
        pub fn resumeValue() i32 {
            return 1;
        }

        /// Preserve the resumed value on the enclosing answer path.
        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };

    /// Continue the transform protocol with the resumed value.
    pub fn apply(value: i32) i32 {
        return value;
    }
};

comptime {
    _ = prompt_support.frontend.transformProgram(DemoPrompt, i32, demo.handle, demo);
}
