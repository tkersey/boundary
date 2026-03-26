const example = @import("example_early_exit");

/// Stable bridge case id for the early-exit example.
pub const bridge_case_id = "early_exit";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/early_exit.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("early_exit.zig");

/// Run the canonical early-exit example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
