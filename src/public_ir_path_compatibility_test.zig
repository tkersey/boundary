const std = @import("std");

test "retained public_ir source path stays source-compatible" {
    const public_ir = @import("public_ir.zig");

    try std.testing.expect(@hasDecl(public_ir, "Program"));
    try std.testing.expect(@hasDecl(public_ir, "compile"));
}
