const std = @import("std");

test "retained shift_agent_vm source path stays source-compatible" {
    const shift_agent_vm = @import("shift_agent_vm.zig");

    try std.testing.expect(@hasDecl(shift_agent_vm, "host"));
    try std.testing.expect(@hasDecl(shift_agent_vm, "runtime"));
    try std.testing.expect(@hasDecl(shift_agent_vm.host, "Adapter"));
    try std.testing.expect(@hasDecl(shift_agent_vm.runtime, "runArtifact"));
}
