const prompt_support = @import("prompt_support");

const DemoError = error{Boom};
const DemoPrompt = prompt_support.Prompt(.resume_or_return, i32, i32, DemoError);
const Decision = prompt_support.ResumeOrReturn(i32, i32);

const demo = struct {
    const handle = struct {
        /// Exercise the error-carrying optional-resumption protocol shape.
        pub fn resumeOrReturn() !Decision {
            return Decision.resumeWith(1);
        }

        /// Preserve the resumed value on the enclosing answer path.
        pub fn afterResume(value: i32) !i32 {
            return value;
        }
    };

    /// Continue the optional-resumption protocol when the error path is not taken.
    pub fn apply(value: i32) !i32 {
        return value;
    }
};

comptime {
    _ = prompt_support.frontend.choiceProgram(DemoPrompt, i32, demo.handle, demo);
}
