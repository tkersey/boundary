const shift = @import("shift");
const prompt_support = shift.internal;

const NoError = error{};
const DemoPrompt = prompt_support.Prompt(.direct_return, i32, i32, NoError);

const demo = struct {
    const handle = struct {
        /// Return the enclosing answer directly for the protocol surface smoke check.
        pub fn directReturn() i32 {
            return 7;
        }
    };
};

comptime {
    _ = prompt_support.frontend.abortProgram(DemoPrompt, demo.handle);
}
