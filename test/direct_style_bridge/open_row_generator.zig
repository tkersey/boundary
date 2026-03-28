const example = @import("example_open_row_generator");

/// Stable bridge case id for the open-row generator example.
pub const bridge_case_id = "open_row_generator";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/open_row_generator.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("open_row_generator.zig");

/// Run the canonical open-row generator example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
