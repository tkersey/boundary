const ability_agent_vm = @import("src/ability_agent_vm.zig");

/// Ordinary consumer compile witness for the retained source-path surface.
pub fn main() void {
    _ = ability_agent_vm.host.Adapter;
    _ = ability_agent_vm.runtime.runArtifact;
}
