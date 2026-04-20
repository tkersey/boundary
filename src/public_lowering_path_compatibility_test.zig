const std = @import("std");

test "retained public_lowering source path stays source-compatible" {
    const public_lowering = @import("public_lowering.zig");

    try std.testing.expect(@hasDecl(public_lowering, "ProgramPlan"));
    try std.testing.expect(@hasDecl(public_lowering, "lowerAt"));
}
