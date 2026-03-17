const prompt_support = @import("prompt_support");
const shift = @import("shift");

const DemoError = error{Boom};
const DemoPrompt = prompt_support.Prompt(.direct_return, i32, i32, DemoError);

const demo = struct {
    const handle = struct {
        /// Exercise the error-carrying direct-return protocol shape.
        pub fn directReturn() shift.ResetError(DemoError)!i32 {
            return error.Boom;
        }
    };
};

comptime {
    _ = prompt_support.frontend.abortProgram(DemoPrompt, demo.handle);
}
