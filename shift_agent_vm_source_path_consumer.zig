/// Marks this compile as the ordinary source-path consumer witness.
pub const source_path_consumer_mode = true;

const shift_agent_vm = @import("src/shift_agent_vm.zig");

/// Ordinary consumer compile witness for the retained source-path surface.
pub fn main() void {
    _ = shift_agent_vm.host.Adapter;
    _ = shift_agent_vm.runtime.runArtifact;
}
