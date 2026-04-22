const shift_agent_vm = @import("src/shift_agent_vm.zig");

/// Ordinary consumer compile witness for the retained source-path surface.
pub fn main() void {
    _ = shift_agent_vm.host.Adapter;
    _ = shift_agent_vm.runtime.runArtifact;
}
