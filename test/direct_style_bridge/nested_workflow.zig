const example = @import("example_nested_workflow");

/// Stable bridge case id for the nested workflow example.
pub const bridge_case_id = "nested_workflow";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/nested_workflow.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("nested_workflow.zig");

/// Run the canonical nested workflow example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
