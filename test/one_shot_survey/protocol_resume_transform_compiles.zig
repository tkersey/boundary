const shift = @import("shift");

const NoError = error{};
const DemoPrompt = shift.Prompt(.resume_then_transform, i32, i32, NoError);

const demo = struct {
    var prompt_ptr: ?*const DemoPrompt = null;

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

    fn body() shift.ResetError(NoError)!i32 {
        const value = try shift.shift(i32, prompt_ptr.?, handle);
        return value;
    }
};

comptime {
    _ = demo.body;
}
