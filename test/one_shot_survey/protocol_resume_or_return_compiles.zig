const prompt_support = @import("prompt_support");

const NoError = error{};
const DemoPrompt = prompt_support.Prompt(.resume_or_return, i32, i32, NoError);
const Decision = prompt_support.ResumeOrReturn(i32, i32);

const demo = struct {
    const handle = struct {
        /// Exercise the optional-resumption protocol in the resume branch.
        pub fn resumeOrReturn() Decision {
            return Decision.resumeWith(1);
        }

        /// Preserve the resumed value on the enclosing answer path.
        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };

    /// Continue the optional-resumption protocol with the resumed value.
    pub fn apply(value: i32) i32 {
        return value;
    }
};

comptime {
    _ = prompt_support.frontend.choiceProgram(DemoPrompt, i32, demo.handle, demo);
}
