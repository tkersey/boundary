const example = @import("example_optional_basic");

/// Stable bridge case id for the optional effect example.
pub const bridge_case_id = "optional_basic";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/optional_basic.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("optional_basic.zig");

/// Run the canonical optional effect example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
