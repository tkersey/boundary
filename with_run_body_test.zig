const shift = @import("src/root.zig");
const std = @import("std");

test "body with run decl" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const body_spec = struct {
        /// Run the body through the public one-argument `run` hook.
        pub fn run(eff: anytype) i32 {
            _ = eff;
            return 1;
        }
    };
    const result = shift.with(&runtime, .{}, body_spec);
    try std.testing.expectEqual(@as(i32, 1), result.value);
}
