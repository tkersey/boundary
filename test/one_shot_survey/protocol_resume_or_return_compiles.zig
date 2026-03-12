const shift = @import("shift");

const NoError = error{};
const DemoPrompt = shift.Prompt(.resume_or_return, i32, i32, NoError);
const Decision = shift.ResumeOrReturn(i32, i32);

const demo = struct {
    var prompt_ptr: ?*const DemoPrompt = null;

    const handle = struct {
        /// Exercise the optional-resumption protocol in the resume branch.
        pub fn resumeOrReturn() Decision {
            return Decision.resumeWith(1);
        }

        fn afterResume(value: i32) i32 {
            return value;
        }
    };

    fn body() shift.ResetError(NoError)!i32 {
        const value = try shift.shift(i32, prompt_ptr.?, handle);
        return value;
    }
};

comptime {
    _ = demo.body;
}
