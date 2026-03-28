const example = @import("example_open_row_abortive_validation");

/// Stable internal proof case id; the legacy `bridge_case_id` name stays for the private seam.
pub const bridge_case_id = "open_row_abortive_validation";
/// Canonical path for this internal proof fixture wrapper.
pub const source_path = "test/direct_style_bridge/open_row_abortive_validation.zig";
/// Embedded fixture source consumed by fail-closed internal proof admission.
pub const source = @embedFile("open_row_abortive_validation.zig");

/// Replay the canonical open-row abortive validation example through the internal proof fixture seam.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
