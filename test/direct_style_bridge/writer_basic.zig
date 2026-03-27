const example = @import("example_writer_basic");

/// Stable bridge case id for the writer example.
pub const bridge_case_id = "writer_basic";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/writer_basic.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("writer_basic.zig");

/// Run the canonical writer example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
