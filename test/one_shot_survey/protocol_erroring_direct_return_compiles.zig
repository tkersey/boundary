const shift = @import("shift");

const DemoError = error{Boom};
const DemoPrompt = shift.Prompt(.direct_return, i32, i32, DemoError);

const demo = struct {
    const handle = struct {
        /// Exercise the error-carrying direct-return protocol shape.
        pub fn directReturn() shift.ResetError(DemoError)!i32 {
            return error.Boom;
        }
    };
};

comptime {
    _ = shift.frontend.abortProgram(DemoPrompt, demo.handle);
}
