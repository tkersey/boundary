const shift = @import("shift");

const DemoError = error{Boom};
const DemoPrompt = shift.Prompt(.resume_or_return, i32, i32, DemoError);
const Decision = shift.ResumeOrReturn(i32, i32);

const demo = struct {
    const handle = struct {
        /// Exercise the error-carrying optional-resumption protocol shape.
        pub fn resumeOrReturn() shift.ResetError(DemoError)!Decision {
            return Decision.resumeWith(1);
        }

        /// Preserve the resumed value on the enclosing answer path.
        pub fn afterResume(value: i32) shift.ResetError(DemoError)!i32 {
            return value;
        }
    };

    /// Continue the optional-resumption protocol when the error path is not taken.
    pub fn apply(value: i32) shift.ResetError(DemoError)!i32 {
        return value;
    }
};

comptime {
    _ = shift.frontend.choiceProgram(DemoPrompt, i32, demo.handle, demo);
}
