const example = @import("example_nested_workflow");

/// Stable internal proof case id; the legacy `bridge_case_id` name stays for the private seam.
pub const bridge_case_id = "nested_workflow";
/// Canonical path for this internal proof fixture wrapper.
pub const source_path = "test/direct_style_bridge/nested_workflow.zig";
/// Embedded fixture source consumed by fail-closed internal proof admission.
pub const source = @embedFile("nested_workflow.zig");

/// Replay the canonical nested workflow example through the internal proof fixture seam.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
