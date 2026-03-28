const example = @import("example_open_row_artifact_search");

/// Stable bridge case id for the open-row artifact search example.
pub const bridge_case_id = "open_row_artifact_search";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/open_row_artifact_search.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("open_row_artifact_search.zig");

/// Run the canonical open-row artifact search example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
