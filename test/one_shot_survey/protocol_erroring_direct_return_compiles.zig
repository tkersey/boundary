const shift = @import("shift");

const DemoError = error{Boom};
const DemoPrompt = shift.Prompt(.direct_return, i32, i32, DemoError);

const demo = struct {
    var prompt_ptr: ?*const DemoPrompt = null;

    const handle = struct {
        /// Exercise the error-carrying direct-return protocol shape.
        pub fn directReturn() shift.ResetError(DemoError)!i32 {
            return error.Boom;
        }
    };

    fn body() shift.ResetError(DemoError)!i32 {
        _ = try shift.shift(void, prompt_ptr.?, handle);
        return 9;
    }
};

comptime {
    _ = demo.body;
}
