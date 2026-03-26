const example = @import("example_state_basic");

/// Stable bridge case id for the state example.
pub const bridge_case_id = "state_basic";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/state_basic.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("state_basic.zig");

/// Run the canonical state example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
