const std = @import("std");
const data = @import("boundary_data");
test "pure package module admits scalar data without authoring imports" {
    try std.testing.expectEqual(@as(?usize, 8), data.scalar.width(.u64));
}
