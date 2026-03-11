const shift = @import("shift");

const NoError = error{};
const DemoPrompt = shift.Prompt(.direct_return, i32, i32, NoError);

const demo = struct {
    var prompt_ptr: ?*const DemoPrompt = null;

    const handle = struct {
        /// Return the enclosing answer directly for the protocol surface smoke check.
        pub fn directReturn() i32 {
            return 7;
        }
    };

    fn body() shift.ResetError(NoError)!i32 {
        _ = try shift.shift(void, prompt_ptr.?, handle);
        return 9;
    }
};

comptime {
    _ = demo.body;
}
