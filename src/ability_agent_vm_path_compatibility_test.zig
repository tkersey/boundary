const std = @import("std");

test "retained ability_agent_vm source path stays source-compatible" {
    const ability_agent_vm = @import("ability_agent_vm.zig");

    try std.testing.expect(@hasDecl(ability_agent_vm, "host"));
    try std.testing.expect(@hasDecl(ability_agent_vm, "runtime"));
    try std.testing.expect(@hasDecl(ability_agent_vm.host, "Adapter"));
    try std.testing.expect(@hasDecl(ability_agent_vm.runtime, "runArtifact"));
}
