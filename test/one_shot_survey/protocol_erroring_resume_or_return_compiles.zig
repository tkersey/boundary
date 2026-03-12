const shift = @import("shift");

const DemoError = error{Boom};
const DemoPrompt = shift.Prompt(.resume_or_return, i32, i32, DemoError);
const Decision = shift.ResumeOrReturn(i32, i32);

const demo = struct {
    var prompt_ptr: ?*const DemoPrompt = null;

    const handle = struct {
        /// Exercise the error-carrying optional-resumption protocol shape.
        pub fn resumeOrReturn() shift.ResetError(DemoError)!Decision {
            return Decision.resumeWith(1);
        }

        fn afterResume(value: i32) shift.ResetError(DemoError)!i32 {
            return value;
        }
    };

    fn body() shift.ResetError(DemoError)!i32 {
        const value = try shift.shift(i32, prompt_ptr.?, handle);
        return value;
    }
};

comptime {
    _ = demo.body;
}
