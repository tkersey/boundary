const shift = @import("shift");
const std = @import("std");

const state_spec = struct {
    /// Prompt tag.
    pub const tag = struct {};
    /// Outbound request type.
    pub const Request = void;
    /// Resume value type.
    pub const Resume = i32;
    /// Final answer type.
    pub const Answer = i32;
    /// User error surface.
    pub const ErrorSet = error{};
};

const demo = struct {
    var resumed: i32 = 0;

    fn body() shift.ResetError(state_spec.ErrorSet)!state_spec.Answer {
        const current = try shift.shift(state_spec, {});
        return current + 1;
    }
};

/// Run the state example.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var step = try shift.reset(state_spec, &runtime, demo.body);
    const answer = while (true) switch (step) {
        .complete => |value| break value,
        .suspended => |*suspension| {
            _ = suspension.request;
            demo.resumed = 41;
            step = try suspension.resumeWith(demo.resumed);
        },
    };

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("answer={d} resumed={d}\n", .{ answer, demo.resumed });
    try stdout.flush();
}
