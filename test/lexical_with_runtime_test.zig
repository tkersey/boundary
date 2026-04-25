const std = @import("std");

test "legacy lexical runtime witnesses are retired from the compiled ability.with suite" {
    try std.testing.expect(true);
}
