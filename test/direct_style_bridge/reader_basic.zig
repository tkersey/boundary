const example = @import("example_reader_basic");

/// Stable bridge case id for the reader example.
pub const bridge_case_id = "reader_basic";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/reader_basic.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("reader_basic.zig");

/// Run the canonical reader example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
