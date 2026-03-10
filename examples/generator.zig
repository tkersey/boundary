const example_driver = @import("example_driver");
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

const driver = struct {
    fn handle(_: *@This(), value: generator_spec.Request) anyerror!example_driver.Decision(generator_spec) {
        demo.yielded[demo.yield_count] = value;
        demo.yield_count += 1;
        return .{ .resume_value = {} };
    }
};

/// Run the direct-style generator example.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var loop_driver: driver = .{};
    switch (try example_driver.run(generator_spec, &runtime, demo.body, &loop_driver, driver.handle)) {
        .complete => {},
        .cancelled => unreachable,
    }

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
