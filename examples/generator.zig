const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const DemoPrompt = shift.Prompt(.resume_then_transform, void, void, NoError);

const demo = struct {
    var prompt_ptr: ?*const DemoPrompt = null;
    var yielded = [_]i32{ 0, 0, 0 };
    var yield_count: usize = 0;
    var pending_value: i32 = 0;

    const handle_yield = struct {
        /// Record the yielded value before resuming the generator body.
        pub fn resumeValue() void {
            yielded[yield_count] = pending_value;
            yield_count += 1;
        }

        /// Complete the yield protocol after the body resumes.
        pub fn afterResume(_: void) void {
            // Intentionally empty: the resumed generator body owns completion.
        }
    };

    fn yieldValue(value: i32) shift.ResetError(NoError)!void {
        pending_value = value;
        _ = try shift.shift(void, prompt_ptr.?, handle_yield);
    }

    fn body() shift.ResetError(NoError)!void {
        yield_count = 0;
        try yieldValue(1);
        try yieldValue(2);
        try yieldValue(3);
    }
};

/// Run the direct-style generator example.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;

    try shift.reset(&runtime, &prompt, demo.body);

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    var i: usize = 0;
    while (i < demo.yield_count) : (i += 1) {
        try stdout.print("yield={d}\n", .{demo.yielded[i]});
    }
    try stdout.print("done={d}\n", .{demo.yield_count});
    try stdout.flush();
}
