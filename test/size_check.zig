const shift = @import("shift");
const std = @import("std");

test "continuation shell stays compact" {
    const NoError = error{};
    const DemoPrompt = shift.Prompt(void, NoError);
    try std.testing.expect(@sizeOf(shift.Continuation(void, DemoPrompt)) <= 2 * @sizeOf(usize));
}

test "guard surface is not public" {
    try std.testing.expect(!@hasDecl(shift, "NoShiftGuard"));
}

test "runtime defaults stay explicit" {
    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    try std.testing.expectEqual(@as(usize, 256 * 1024), runtime.options.stack_bytes);
    try std.testing.expectEqual(@as(usize, 1), runtime.options.guard_pages);
}
