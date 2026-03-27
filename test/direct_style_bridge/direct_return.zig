const parity_scenarios = @import("parity_scenarios");

/// Stable bridge case id for the direct-return witness.
pub const bridge_case_id = "direct_return";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/direct_return.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("direct_return.zig");

/// Run the canonical direct-return witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll(parity_scenarios.findWitness(bridge_case_id).?.expected_transcript);
}
