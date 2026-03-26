const example = @import("example_algebraic_abortive_validation");

/// Stable bridge case id for the algebraic abortive validation example.
pub const bridge_case_id = "algebraic_abortive_validation";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/algebraic_abortive_validation.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("algebraic_abortive_validation.zig");

/// Run the canonical algebraic abortive validation example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
