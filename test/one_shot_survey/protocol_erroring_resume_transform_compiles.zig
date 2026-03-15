const shift = @import("shift");

const DemoError = error{Boom};
const DemoPrompt = shift.Prompt(.resume_then_transform, i32, i32, DemoError);

const demo = struct {
    const handle = struct {
        /// Exercise the error-carrying resume protocol shape.
        pub fn resumeValue() shift.ResetError(DemoError)!i32 {
            return error.Boom;
        }

        /// Preserve the resumed value when the error path is not taken.
        pub fn afterResume(value: i32) shift.ResetError(DemoError)!i32 {
            return value;
        }
    };

    /// Continue the transform protocol when the error path is not taken.
    pub fn apply(value: i32) shift.ResetError(DemoError)!i32 {
        return value;
    }
};

comptime {
    _ = shift.frontend.transformProgram(DemoPrompt, i32, demo.handle, demo);
}
