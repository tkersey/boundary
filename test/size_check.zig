const shift = @import("shift");
const std = @import("std");

test "continuation shell stays compact" {
    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = void;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = void;
        /// User error surface.
        pub const ErrorSet = error{};
    };
    try std.testing.expect(@sizeOf(shift.Suspension(demo_spec)) <= 2 * @sizeOf(usize));
}

test "runtime defaults stay explicit" {
    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    try std.testing.expectEqual(@as(usize, 256 * 1024), runtime.options.stack_bytes);
    try std.testing.expectEqual(@as(usize, 1), runtime.options.guard_pages);
}
