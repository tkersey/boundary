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

    var outcome = try shift.reset(state_spec, &runtime, demo.body);
    while (true) switch (outcome) {
        .complete => unreachable,
        .cancelled => break,
        .pending => |*pending| {
            demo.resumed = 0;
            outcome = try pending.cancel();
        },
    };

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("cancelled=yes resumed={d}\n", .{demo.resumed});
    try stdout.flush();
}
