const example = @import("example_generator");

/// Stable bridge case id for the generator example.
pub const bridge_case_id = "generator";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/generator.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("generator.zig");

/// Run the canonical generator example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
