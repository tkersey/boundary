const compat_raw = @import("compat_raw");
const std = @import("std");

test "runtime defaults stay explicit" {
    var runtime = compat_raw.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    try std.testing.expectEqual(@as(usize, 256 * 1024), runtime.options.stack_bytes);
    try std.testing.expectEqual(@as(usize, 1), runtime.options.guard_pages);
}

test "runtime option compatibility fields stay source-visible" {
    var runtime = compat_raw.Runtime.init(std.testing.allocator, .{
        .stack_bytes = 4096,
        .guard_pages = 7,
        .max_cached_stacks = 2,
    });
    defer runtime.deinit();

    try std.testing.expectEqual(@as(usize, 4096), runtime.options.stack_bytes);
    try std.testing.expectEqual(@as(usize, 7), runtime.options.guard_pages);
    try std.testing.expectEqual(@as(usize, 2), runtime.options.max_cached_stacks);
}
