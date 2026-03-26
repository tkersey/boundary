const parity_scenarios = @import("parity_scenarios");

/// Stable bridge case id for the ATM witness.
pub const bridge_case_id = "atm_resume_transform";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/atm_resume_transform.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("atm_resume_transform.zig");

/// Run the canonical ATM witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll(parity_scenarios.findWitness(bridge_case_id).?.expected_transcript);
}
