const example = @import("example_open_row_artifact_search");

/// Stable internal proof case id; the legacy `bridge_case_id` name stays for the private seam.
pub const bridge_case_id = "open_row_artifact_search";
/// Canonical path for this internal proof fixture wrapper.
pub const source_path = "test/direct_style_bridge/open_row_artifact_search.zig";
/// Embedded fixture source consumed by fail-closed internal proof admission.
pub const source = @embedFile("open_row_artifact_search.zig");

/// Replay the canonical open-row artifact search example through the internal proof fixture seam.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
