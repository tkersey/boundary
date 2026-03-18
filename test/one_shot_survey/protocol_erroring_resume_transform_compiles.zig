const prompt_support = @import("prompt_support");
const shift = @import("shift");

const DemoError = error{Boom};
const DemoPrompt = prompt_support.Prompt(.resume_then_transform, i32, i32, DemoError);

const demo = struct {
    const handle = struct {
        /// Exercise the error-carrying resume protocol shape.
        pub fn resumeValue() !i32 {
            return error.Boom;
        }

        /// Preserve the resumed value when the error path is not taken.
        pub fn afterResume(value: i32) !i32 {
            return value;
        }
    };

    /// Continue the transform protocol when the error path is not taken.
    pub fn apply(value: i32) !i32 {
        return value;
    }
};

comptime {
    _ = prompt_support.frontend.transformProgram(DemoPrompt, i32, demo.handle, demo);
}
