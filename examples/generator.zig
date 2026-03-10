const shift = @import("shift");
const std = @import("std");

const generator_spec = struct {
    /// Prompt tag.
    pub const tag = struct {};
    /// Outbound request type.
    pub const Request = i32;
    /// Resume value type.
    pub const Resume = void;
    /// Final answer type.
    pub const Answer = void;
    /// User error surface.
    pub const ErrorSet = error{};
};

const demo = struct {
    var yielded = [_]i32{ 0, 0, 0 };
    var yield_count: usize = 0;
    fn yieldValue(value: i32) shift.ResetError(generator_spec.ErrorSet)!void {
        _ = try shift.shift(generator_spec, value);
    }

    fn body() shift.ResetError(generator_spec.ErrorSet)!generator_spec.Answer {
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

    var outcome = try shift.reset(generator_spec, &runtime, demo.body);
    while (true) switch (outcome) {
        .complete => break,
        .cancelled => unreachable,
        .pending => |*pending| {
            demo.yielded[demo.yield_count] = pending.request();
            demo.yield_count += 1;
            outcome = try pending.proceed();
        },
    };

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
