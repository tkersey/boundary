const std = @import("std");
const shift = @import("src/root.zig");

test "body with run decl" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const Body = struct {
        pub fn run(eff: anytype) i32 {
            _ = eff;
            return 1;
        }
    };
    const result = shift.with(&runtime, .{}, Body);
    try std.testing.expectEqual(@as(i32, 1), result.value);
}
