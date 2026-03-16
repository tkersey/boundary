const ordinary = @import("ordinary_zig_registry");
const ordinary_zig_lowering = @import("ordinary_zig_lowering");
const std = @import("std");

test "ordinary Zig registry keeps the exact wave-one case count" {
    try std.testing.expectEqual(@as(usize, 8), ordinary.cases.len);
    for (ordinary.cases) |case| {
        try std.testing.expect(case.status == .green);
    }
}

test "ordinary Zig lowering rejects unsupported fixture ids" {
    const unsupported_fixture = struct {
        /// Stable unsupported ordinary-Zig case id.
        pub const ordinary_case_id = "ordinary.recursion";
    };

    try std.testing.expectError(error.UnsupportedOrdinaryCase, ordinary_zig_lowering.lowerFixture(unsupported_fixture));
}
