const shift = @import("shift");

const DemoError = error{Boom};
const DemoPrompt = shift.Prompt(.resume_then_transform, i32, i32, DemoError);

const demo = struct {
    var prompt_ptr: ?*const DemoPrompt = null;

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

    fn body() shift.ResetError(DemoError)!i32 {
        const value = try shift.shift(i32, prompt_ptr.?, handle);
        return value;
    }
};

comptime {
    _ = demo.body;
}
